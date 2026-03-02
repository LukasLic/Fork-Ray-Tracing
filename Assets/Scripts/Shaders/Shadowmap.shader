Shader "Hidden/Shadowmap"
{
    Properties
    {
        _TexRT ("Raytraced Base (tex_rt)", 2D) = "black" {}
        _TexShadow ("Raytraced With Extra Object (tex_shadow)", 2D) = "black" {}

        _AppliedShadowScale ("Applied Shadow Strength Scale", Float) = 1.0

        _Denoise ("Denoise (0 or 3)", Int) = 3

        _LightScale ("Extra Light Scale", Float) = 1.0
        _ShadowScale ("Shadow Strength Scale", Float) = 40.0

        // Ignore tiny positive RGB deltas (reflection/light). Anything <= threshold is treated as 0 to reduce noise/shimmer.
        _LightThreshold ("Extra Light Threshold", Float) = 0.0
        // Ignore tiny negative luminance deltas (shadowing). Anything <= threshold is treated as 0 to reduce noise/speckle in alpha.
        _ShadowThreshold ("Shadow Threshold", Float) = 0.0
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

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _TexRT;
            float4 _TexRT_TexelSize; // x=1/width, y=1/height, z=width, w=height

            sampler2D _TexShadow;

            float _AppliedShadowScale;

            int _Denoise;

            float _LightScale;
            float _ShadowScale;

            float _LightThreshold;
            float _ShadowThreshold;

            float Luminance(float3 rgb)
            {
                return dot(rgb, float3(0.2126, 0.7152, 0.0722));
            }

            // Returns:
            // rgb = extra light (tex_shadow - tex_rt, clamped to >= 0)
            //  a  = shadow amount in luminance space (lum_rt - lum_shadow, clamped to >= 0)
            float4 SampleDelta(float2 uv)
            {
                float3 rt = saturate(tex2D(_TexRT, uv).rgb);
                float3 sh = saturate(tex2D(_TexShadow, uv).rgb);

                float3 extra = max(sh - rt, 0.0);
                float shadow = max(Luminance(rt) - Luminance(sh), 0.0);

                // Optional thresholds to cut tiny noise
                extra = max(extra - _LightThreshold, 0.0);
                shadow = max(shadow - _ShadowThreshold, 0.0);

                return float4(extra, shadow);
            }

            float4 SampleDeltaDenoised3x3(float2 uv)
            {
                float2 t = _TexRT_TexelSize.xy;

                // 3x3 Gaussian kernel:
                // 1 2 1
                // 2 4 2   / 16
                // 1 2 1
                float4 sum = 0;

                sum += SampleDelta(uv + t * float2(-1, -1)) * 1.0;
                sum += SampleDelta(uv + t * float2( 0, -1)) * 2.0;
                sum += SampleDelta(uv + t * float2( 1, -1)) * 1.0;

                sum += SampleDelta(uv + t * float2(-1,  0)) * 2.0;
                sum += SampleDelta(uv + t * float2( 0,  0)) * 4.0;
                sum += SampleDelta(uv + t * float2( 1,  0)) * 2.0;

                sum += SampleDelta(uv + t * float2(-1,  1)) * 1.0;
                sum += SampleDelta(uv + t * float2( 0,  1)) * 2.0;
                sum += SampleDelta(uv + t * float2( 1,  1)) * 1.0;

                return sum * (1.0 / 16.0);
            }

            float2 SampleShadow(float2 uv)
            {
                float3 rt = saturate(tex2D(_TexRT, uv).rgb);
                float3 sh = saturate(tex2D(_TexShadow, uv).rgb);
                float diff1 = Luminance(rt) - Luminance(sh);
                float diff2 = Luminance(sh) - Luminance(rt);
                float r = max(diff1, 0.0); // Negative difference.
                float g = max(diff2, 0.0); // Positive difference.
                return float2(r, g);
            }

            float2 SampleShadowDenoised3x3(float2 uv)
            {
                float2 t = _TexRT_TexelSize.xy;

                // 3x3 Gaussian kernel:
                // 1 2 1
                // 2 4 2   / 16
                // 1 2 1
                float2 sum = 0;

                sum += SampleShadow(uv + t * float2(-1, -1)) * 1.0;
                sum += SampleShadow(uv + t * float2( 0, -1)) * 2.0;
                sum += SampleShadow(uv + t * float2( 1, -1)) * 1.0;

                sum += SampleShadow(uv + t * float2(-1,  0)) * 2.0;
                sum += SampleShadow(uv + t * float2( 0,  0)) * 4.0;
                sum += SampleShadow(uv + t * float2( 1,  0)) * 2.0;

                sum += SampleShadow(uv + t * float2(-1,  1)) * 1.0;
                sum += SampleShadow(uv + t * float2( 0,  1)) * 2.0;
                sum += SampleShadow(uv + t * float2( 1,  1)) * 1.0;

                return sum * (1.0 / 16.0);
            }

            float4 frag(v2f i) : SV_Target
            {
                // float4 d = (_Denoise >= 3) ? SampleDeltaDenoised3x3(i.uv) : SampleDelta(i.uv);

                // // RGB: extra reflected light (can be HDR). Keep >= 0.
                // float3 extraLight = max(d.rgb * _LightScale, 0.0);

                // // Alpha: 1 means no shadow, 0 means strong shadow.
                // float shadowStrength = max(d.a * _ShadowScale, 0.0);
                // float alpha = 1.0 - saturate(shadowStrength);

                // return float4(extraLight, alpha);

                // float3 res = float3(alpha,0,0);
                // return float4(res, 1);

                // ######################################################

                // float3 rt = saturate(tex2D(_TexRT, i.uv).rgb);
                // float3 sh = saturate(tex2D(_TexShadow, i.uv).rgb);

                // // Difference between sh and rt (in luminance).
                // float diff1 = Luminance(rt) - Luminance(sh);
                // float diff2 = Luminance(sh) - Luminance(rt);

                // float r = max(diff1, 0.0); // Negative difference.
                // float g = max(diff2, 0.0); // Positive difference.
                // float b = 0.0;
                // return float4(r, g, b, 1.0);

                // ######################################################

                // float4 rt = tex2D(_TexShadow, i.uv).rgba;
                // return float4(rt.a, 0, 0, 1.0); // return alpha of _TexRT for debugging UVs

                // ######################################################
                float2 average = SampleShadowDenoised3x3(i.uv);
                float r = average.x; // Negative difference (shadow).
                float g = average.y; // Positive difference (shadow).
                float b = 0.0;
                // return float4(r, g, b, 1.0);

                float3 original = saturate(tex2D(_TexRT, i.uv).rgb);
                float3 shadowed = original * (1.0 - r * pow(_AppliedShadowScale, 2.0));

                float4 shadowMask = tex2D(_TexShadow, i.uv).rgba;
                
                float3 final = lerp(shadowed, shadowMask.rgb, saturate(shadowMask.a));

                return float4(saturate(final), 1.0);
            }
            ENDCG
        }
    }
}