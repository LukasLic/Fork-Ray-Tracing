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

                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                float3 rayOrigin = _WorldSpaceCameraPos;


                // return fixed4(depth / 5.0f, 0.0, 0.0, 1.0);

                float4 cur = tex2D(_MainTex, i.uv);
                float curDist = depth;

                if (curDist >= _MaxDistance - 1e-3)
                    return fixed4(0.0, 0.0, 0.0, 1.0);

                float3 curDir = CurPrimaryRayDirWS(i.uv);
                float3 worldPos = _WorldSpaceCameraPos + curDir * curDist;

                float2 suv;
                if (!WorldToSnapshotUV(worldPos, suv))
                    return fixed4(0.0, 0.0, 0.0, 1.0);

                snap = tex2D(_Snapshot01, suv);
                float snapDist = snap.a;

                if (snapDist >= _MaxDistance - 1e-3)
                    return fixed4(cur.rgb, 1.0);

                float expected = length(worldPos - _SnapCamPos);
                float eps = max(_DepthEps, expected * _DepthEpsRelative);

                if (abs(expected - snapDist) <= eps)
                    return fixed4(snap.rgb, 1.0);

                return fixed4(0.0, 0.0, 0.0, 1.0);
            }
            ENDCG
        }
    }
}
