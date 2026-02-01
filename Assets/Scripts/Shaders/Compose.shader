Shader "Hidden/Compose"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Snapshot01 ("Snapshot01", 2D) = "black" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _Snapshot01;
            float4 _Snapshot01_TexelSize; // x=1/width, y=1/height, z=width, w=height
            int _Denoise;

            float4 SampleSnapshot01Denoised5x5(float2 uv)
            {
                float2 t = _Snapshot01_TexelSize.xy;

                float w0 = 1.0;
                float w1 = 4.0;
                float w2 = 6.0;

                // 5x5 Gaussian kernel:
                // 1  4  6  4  1
                // 4 16 24 16  4
                // 6 24 36 24  6   / 256
                // 4 16 24 16  4
                // 1  4  6  4  1
                float4 sum = 0;

                // Row -2
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-2, -2)) * (w0 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1, -2)) * (w1 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0, -2)) * (w2 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1, -2)) * (w1 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 2, -2)) * (w0 * w0));

                // Row -1
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-2, -1)) * (w0 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1, -1)) * (w1 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0, -1)) * (w2 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1, -1)) * (w1 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 2, -1)) * (w0 * w1));

                // Row 0
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-2,  0)) * (w0 * w2));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1,  0)) * (w1 * w2));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0,  0)) * (w2 * w2));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1,  0)) * (w1 * w2));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 2,  0)) * (w0 * w2));

                // Row +1
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-2,  1)) * (w0 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1,  1)) * (w1 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0,  1)) * (w2 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1,  1)) * (w1 * w1));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 2,  1)) * (w0 * w1));

                // Row +2
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-2,  2)) * (w0 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1,  2)) * (w1 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0,  2)) * (w2 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1,  2)) * (w1 * w0));
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 2,  2)) * (w0 * w0));

                return sum * (1.0 / 256.0);
            }

            float4 SampleSnapshot01Denoised3x3(float2 uv)
            {
                float2 t = _Snapshot01_TexelSize.xy;

                // 3x3 Gaussian kernel:
                // 1 2 1
                // 2 4 2   / 16
                // 1 2 1
                float4 sum = 0;

                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1, -1)) * 1.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0, -1)) * 2.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1, -1)) * 1.0);

                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1,  0)) * 2.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0,  0)) * 4.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1,  0)) * 2.0);

                sum += saturate(tex2D(_Snapshot01, uv + t * float2(-1,  1)) * 1.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 0,  1)) * 2.0);
                sum += saturate(tex2D(_Snapshot01, uv + t * float2( 1,  1)) * 1.0);

                return sum * (1.0 / 16.0);
            }

            float4 frag (v2f i) : SV_Target
            {
                if(_Denoise >= 5)
                {
                    float4 s01 = SampleSnapshot01Denoised5x5(i.uv);
                    return float4(saturate(s01.rgb), 0);
                }

                if(_Denoise >= 3)
                {
                    float4 s01 = SampleSnapshot01Denoised3x3(i.uv);
                    return float4(saturate(s01.rgb), 0);
                }
                
                float4 s01 = tex2D(_Snapshot01, i.uv);
                return float4(saturate(s01.rgb), 0);
            }
            ENDCG
        }
    }
}
