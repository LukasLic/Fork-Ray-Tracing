Shader "Hidden/Compose"
{
 //    Properties
	// {
	// 	_MainTex ("Texture", 2D) = "white" {}
	// }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;      // current view: rgb + dist in a
            sampler2D _Snapshot01;   // snapshot:      rgb + dist in a
            sampler2D _CameraDepthTexture;

            float3 _CurViewParams;           // (planeW, planeH, focusDist)
            float4x4 _CurCamLocalToWorld;    // current camera local->world

            float4x4 _SnapViewProj;          // snapshot GPU VP (proj * view)
            float3 _SnapCamPos;              // snapshot camera world pos

            float _MaxDistance;              // eg 5000
            float _DepthEps;                 // eg 0.05
            float _DepthEpsRelative;         // eg 0.002

            int _Smooth;
            float _sigmaColor; // eg 0.15
            float _sigmaDist;  // eg 0.10
            float _sigmaDistScale; // eg 0.08

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float3 CurPrimaryRayDirWS(float2 uv)
            {
                float3 viewPlaneLocal = float3(uv - 0.5, 1.0) * _CurViewParams;
                float3 viewPlaneWorld = mul(_CurCamLocalToWorld, float4(viewPlaneLocal, 1.0)).xyz;
                return normalize(viewPlaneWorld - _WorldSpaceCameraPos);
            }

            bool WorldToSnapshotUV(float3 worldPos, out float2 snapUV)
            {
                float4 sc = mul(_SnapViewProj, float4(worldPos, 1.0));
                if (sc.w <= 0.0) { snapUV = 0; return false; }

                snapUV = sc.xy / sc.w * 0.5 + 0.5;
                if (snapUV.x < 0.0 || snapUV.x > 1.0 || snapUV.y < 0.0 || snapUV.y > 1.0) return false;

                return true;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float4 snap = tex2D(_Snapshot01, i.uv);

                // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                // +++ FIREFLY DENOISER ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

                float curDist = snap.a;

                if(_Smooth == 1 && curDist > 1e-4)
                {
                    if (curDist < _MaxDistance - 1e-3)
                    {
                            float2 texel = 1.0 / _ScreenParams.xy;

                            // Local tuning constants.
                            const float kOutlier = 4.0;          // higher = less aggressive, lower = more aggressive
                            const float minDepthGate = 0.05;     // meters
                            const float depthGateScale = 0.02;   // relative to center distance
                            const float eps = 1e-4;

                            float depthGate = max(minDepthGate, snap.a * depthGateScale);

                            // Luma helper (inline).
                            float centerL = dot(snap.rgb, float3(0.2126, 0.7152, 0.0722));

                            // Pass 1: compute neighbor mean (exclude center).
                            float3 sumRGB = 0.0;
                            float  sumL   = 0.0;
                            float  count  = 0.0;

                            [unroll]
                            for (int y = -1; y <= 1; y++)
                            {
                                [unroll]
                                for (int x = -1; x <= 1; x++)
                                {
                                    if (x == 0 && y == 0)
                                        continue;

                                    float2 uv = i.uv + float2((float)x, (float)y) * texel;
                                    uv = clamp(uv, texel * 0.5, 1.0 - texel * 0.5);

                                    float4 s = tex2D(_Snapshot01, uv);
                                    s.rgb = saturate(s.rgb);

                                    if (s.a == 0.0)
                                        continue;

                                    // Keep neighbors on the same surface (depth-consistent).
                                    if (abs(s.a - snap.a) > depthGate)
                                        continue;

                                    sumRGB += s.rgb;
                                    float l = dot(s.rgb, float3(0.2126, 0.7152, 0.0722)); // luma formula
                                    sumL += l;
                                    count += 1.0;
                                }
                            }

                            // Not enough neighbors to form a reliable consensus.
                            if (count > 3.0)
                            {
                                float invCount = 1.0 / count;
                                float3 meanRGB = sumRGB * invCount;
                                float  meanL   = sumL   * invCount;

                                // Pass 2: measure how similar the neighbors are (mean absolute deviation in luma).
                                float mad = 0.0;

                                [unroll]
                                for (int y2 = -1; y2 <= 1; y2++)
                                {
                                    [unroll]
                                    for (int x2 = -1; x2 <= 1; x2++)
                                    {
                                        if (x2 == 0 && y2 == 0)
                                            continue;

                                        float2 uv2 = i.uv + float2((float)x2, (float)y2) * texel;
                                        uv2 = clamp(uv2, texel * 0.5, 1.0 - texel * 0.5);

                                        float4 s2 = tex2D(_Snapshot01, uv2);

                                        if (s2.a == 0.0)
                                            continue;

                                        if (abs(s2.a - snap.a) > depthGate)
                                            continue;

                                        float l2 = dot(s2.rgb, float3(0.2126, 0.7152, 0.0722));
                                        mad += abs(l2 - meanL);
                                    }
                                }

                                mad *= invCount;

                                // If neighbors are not similar, do not touch the center (likely an edge or detail).
                                float tightThreshold = max(0.01, abs(meanL) * 0.05);
                                float tight = step(mad, tightThreshold); // 1 when mad <= threshold

                                // How far the center is from the neighborhood consensus.
                                float dev = abs(centerL - meanL);

                                float thresh = kOutlier * (mad + eps);

                                // Blend factor: 0 if not an outlier, approaches 1 as it becomes a stronger outlier.
                                float t = saturate((dev - thresh) / max(dev, eps));
                                t *= tight;

                                float3 rgbFixed = lerp(snap.rgb, meanRGB, t);
                                snap.rgb = rgbFixed;
                            }
                    }
                }

                // --- FIREFLY DENOISER ----------------------------------------------------------------------
                // -------------------------------------------------------------------------------------------

                // +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                // +++ BLUR DENOISER +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

    //             // Local (non-uniform) settings.
    //             // Bigger sigma => more tolerance => more blurring.
				// const float sigmaColor = _sigmaColor; // assumes color roughly in 0..1
				// float sigmaDist = max(_sigmaDist, snap.a * _sigmaDistScale); // distance in meters, scale with depth

    //             float inv2SigmaColor2 = 1.0 / (2.0 * sigmaColor * sigmaColor);
				// float inv2SigmaDist2  = 1.0 / (2.0 * sigmaDist  * sigmaDist);

    //             float curDist = snap.a;

    //             if(_Smooth == 1 && curDist > 1e-4)
    //             {
    //                 if (curDist < _MaxDistance - 1e-3)
    //                 {
    //                     float3 curDir = CurPrimaryRayDirWS(i.uv);
    //                     float3 worldPos = _WorldSpaceCameraPos + curDir * curDist;

    //                     float2 texel = 1.0 / _ScreenParams.xy;

    //                     float3 sumRGB = 0.0;
				// 	    float  sumW   = 0.0;

    //                     //snap.r = saturate(curDist / 15.0f);
    //                     [unroll]
				// 	    for (int y = -1; y <= 1; y++)
				// 	    {
				// 		    [unroll]
				// 		    for (int x = -1; x <= 1; x++)
				// 		    {
    //                             float2 uv = i.uv + float2((float)x, (float)y) * texel;

    //                             // Clamp to valid UVs to avoid sampling outside edges.
				// 			    uv = clamp(uv, texel * 0.5, 1.0 - texel * 0.5);

    //                             float4 s = tex2D(_Snapshot01, uv);

    //                             // Skip invalid samples.
    //                             if(s.a == 0.0) continue;

    //                             // Cheap fixed spatial weights for a 3x3 kernel.
				// 			    float spatialWeight;
				// 			    int ax = (x < 0) ? -x : x;
				// 			    int ay = (y < 0) ? -y : y;

				// 			    if (ax == 0 && ay == 0) spatialWeight = 0.05;
				// 			    else if (ax + ay == 1)  spatialWeight = 0.5;   // N,S,E,W
				// 			    else                    spatialWeight = 0.25;  // diagonals


    //                             float3 dc = s.rgb - snap.rgb;       // per-channel difference vector
				// 			    float  colorDist2 = dot(dc, dc);    // squared Euclidean distance in RGB space (quicker then length)

    //                             float  dd = s.a - snap.a;   // depth difference in meters
				// 			    float  distDiff2 = dd * dd; // squared distance

    //                             // Convert differences into weights using Gaussians falloffs
    //                             float wColor = exp(-colorDist2 * inv2SigmaColor2); // near 1 if colors match
    //                             float wDist  = exp(-distDiff2  * inv2SigmaDist2); // near 1 if depths match

    //                             float w = spatialWeight * wColor * wDist;

    //                             sumRGB += s.rgb * w;
    //                             sumW   += w;
    //                         }
    //                     }

    //                     if (sumW > 0.0)
    //                         snap.rgb = sumRGB / sumW;
    //                 }
    //             }

                // --- BLUR DENOISER -------------------------------------------------------------------------
                // -------------------------------------------------------------------------------------------
                
                // Early exit, skip later Compose logic.
                return fixed4(snap.rgb, 1.0);


                // if(i.uv.y > 0.5)
                // {
                //     if(i.uv.x > 0.5)
                //     {
                //         return tex2D(_Snapshot01, i.uv);
                //     }
                //     else 
                //     {
                //         return tex2D(_MainTex, i.uv);
                //     }
                // }

                // ===========================================================================================
                // ===========================================================================================

                // OLD CODE ??

       //          float3 ViewParams;
			    // float4x4 CamLocalToWorldMatrix;

       //          // return fixed4(depth / 5.0f, 0.0, 0.0, 1.0);

       //          float4 cur = tex2D(_MainTex, i.uv);
       //          float curDist = cur.a;

       //          if (curDist >= _MaxDistance - 1e-3)
       //              return fixed4(0.0, 0.0, 0.0, 1.0);

       //          float3 curDir = CurPrimaryRayDirWS(i.uv);
       //          float3 worldPos = _WorldSpaceCameraPos + curDir * curDist;

       //          float2 suv;
       //          if (!WorldToSnapshotUV(worldPos, suv))
       //              return fixed4(0.0, 0.0, 0.0, 1.0);

       //          snap = tex2D(_Snapshot01, suv);
       //          float snapDist = snap.a;

       //          if (snapDist >= _MaxDistance - 1e-3)
       //              return fixed4(cur.rgb, 1.0);

       //          float expected = length(worldPos - _SnapCamPos);
       //          float eps = max(_DepthEps, expected * _DepthEpsRelative);

       //          if (abs(expected - snapDist) <= eps)
       //              return fixed4(snap.rgb, 1.0);

       //          return fixed4(0.0, 0.0, 0.0, 1.0);
            }
            ENDCG
        }
    }
}
