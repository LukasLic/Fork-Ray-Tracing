Shader "Hidden/DebugPointBillboards"
{
    SubShader
    {
        Tags { "Queue"="Overlay" }
        Pass
        {
            ZTest LEqual
            ZWrite Off
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            StructuredBuffer<float3> _Points;
            float _SizePixels;

            struct v2f
            {
                float4 pos : SV_POSITION;
            };

            float2 CornerForTriVert(uint corner)
            {
                // Two triangles making a quad:
                // 0 (-0.5,-0.5), 1 (0.5,-0.5), 2 (0.5,0.5)
                // 3 (-0.5,-0.5), 4 (0.5,0.5), 5 (-0.5,0.5)
                if (corner == 0) return float2(-0.5, -0.5);
                if (corner == 1) return float2( 0.5, -0.5);
                if (corner == 2) return float2( 0.5,  0.5);
                if (corner == 3) return float2(-0.5, -0.5);
                if (corner == 4) return float2( 0.5,  0.5);
                return float2(-0.5,  0.5);
            }

            v2f vert(uint vid : SV_VertexID)
            {
                v2f o;

                uint pointIndex = vid / 6;
                uint corner = vid % 6;

                float3 wp = _Points[pointIndex];
                float4 clip = mul(UNITY_MATRIX_VP, float4(wp, 1.0));

                float2 cornerOffset = CornerForTriVert(corner);

                // pixels -> NDC
                float2 ndcPerPixel = 2.0 / _ScreenParams.xy;
                float2 ndcOffset = cornerOffset * (_SizePixels * ndcPerPixel);

                // NDC -> clip (multiply by w)
                clip.xy += ndcOffset * clip.w;

                o.pos = clip;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                return fixed4(1, 0, 0, 1);
            }
            ENDCG
        }
    }
}
