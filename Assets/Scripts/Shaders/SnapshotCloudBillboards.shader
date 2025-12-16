Shader "Hidden/SnapshotCloudBillboards"
{
    SubShader
    {
        // Tags { "Queue"="Transparent" }
        Tags { "Queue"="Geometry" "RenderType"="Opaque" }
        Pass
        {
            ZTest LEqual
            ZWrite On
            Cull Off
            Blend Off
            // Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _SnapshotTex;          // rgb + dist in a
            float4 _SnapshotTex_TexelSize;   // x=1/w y=1/h z=w w=h

            float3 _SnapCamPos;
            float3 _SnapViewParams;          // (planeW, planeH, focusDist)
            float4x4 _SnapCamLocalToWorld;

            float _MaxDistance;
            float _SizePixels;
            float _Step;

            struct v2f
            {
                float4 pos   : SV_POSITION;
                float4 col   : TEXCOORD0;
                float  valid : TEXCOORD1;
            };

            float2 CornerForTriVert(uint corner)
            {
                if (corner == 0) return float2(-0.5, -0.5);
                if (corner == 1) return float2( 0.5, -0.5);
                if (corner == 2) return float2( 0.5,  0.5);
                if (corner == 3) return float2(-0.5, -0.5);
                if (corner == 4) return float2( 0.5,  0.5);
                return float2(-0.5,  0.5);
            }

            float3 SnapPrimaryRayDirWS(float2 uv)
            {
                float3 viewPlaneLocal = float3(uv - 0.5, 1.0) * _SnapViewParams;
                float3 viewPlaneWorld = mul(_SnapCamLocalToWorld, float4(viewPlaneLocal, 1.0)).xyz;
                return normalize(viewPlaneWorld - _SnapCamPos);
            }

            v2f vert(uint vid : SV_VertexID)
            {
                v2f o;

                uint triCorner = vid % 6;
                uint pointIndex = vid / 6;

                uint texW = (uint)_SnapshotTex_TexelSize.z;
                uint texH = (uint)_SnapshotTex_TexelSize.w;
                uint step = (uint)max(1.0, _Step);

                uint gridW = max(1u, texW / step);

                uint gx = pointIndex % gridW;
                uint gy = pointIndex / gridW;

                uint x = gx * step;
                uint y = gy * step;

                float2 uv = (float2(x, y) + 0.5) / float2(texW, texH);

                float4 s = tex2Dlod(_SnapshotTex, float4(uv, 0, 0));
                float dist = s.a - 1e-3;

                o.col = float4(s.rgb, 1.0);
                o.valid = dist < (_MaxDistance - 0.05) && dist > 0.05;

                if (o.valid < 0.5)
                {
                    o.pos = float4(2, 2, 0, 1);
                    return o;
                }

                float3 dirWS = SnapPrimaryRayDirWS(uv);
                float3 worldPos = _SnapCamPos + dirWS * dist;

                float4 clip = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                if (clip.w <= 0.0)
                {
                    o.valid = 0;
                    o.pos = float4(2, 2, 0, 1);
                    return o;
                }

                float2 corner = CornerForTriVert(triCorner);

                float2 ndcPerPixel = 2.0 / _ScreenParams.xy;
                float2 ndcOffset = corner * (_SizePixels * ndcPerPixel);

                clip.xy += ndcOffset * clip.w;

                o.pos = clip;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                if (i.valid < 0.5) discard;
                return i.col;
            }

            ENDCG
        }
    }
}
