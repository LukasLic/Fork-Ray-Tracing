# Ray-Tracing
A fairly simple (and slow) ray tracer, coded in C# and HLSL in the Unity engine.<br>
<br>
<br>
Based on a tutorial video series by Sebastian Lague. You can watch some videos from the tutorial series by clicking the images below.
[![Ray Tracing Video](https://raw.githubusercontent.com/SebLague/Images/master/Ray%20Tracing.jpg)](https://youtu.be/Qz0KTGYJtUk)
[![BVH Video](https://github.com/SebLague/Images/blob/master/bvh_thumb.jpg?raw=true)](https://www.youtube.com/watch?v=C1H4zIiCOaI)
<br>
Thanks to [Ray Tracing in One Weekend](https://raytracing.github.io) and [Casual Shadertoy Path Tracing](https://blog.demofox.org/2020/05/25/casual-shadertoy-path-tracing-1-basic-camera-diffuse-emissive/) and [How to Build a BVH](https://jacco.ompf2.com/2022/04/13/how-to-build-a-bvh-part-1-basics/)

// Save and initiatiate
// Send to ShadowDeltaCompose
RenderTexture resultTexture_copy;
RenderTexture resultTexture_shadow;





Shader "Hidden/ShadowDeltaCompose"
{
    Properties
    {
        _TexRT ("Raytraced Base (tex_rt)", 2D) = "black" {}
        _TexShadow ("Raytraced With Extra Object (tex_shadow)", 2D) = "black" {}

        _Denoise ("Denoise (0 or 3)", Int) = 3

        _LightScale ("Extra Light Scale", Float) = 1.0
        _ShadowScale ("Shadow Strength Scale", Float) = 1.0

        _LightThreshold ("Extra Light Threshold", Float) = 0.0
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
                float3 rt = tex2D(_TexRT, uv).rgb;
                float3 sh = tex2D(_TexShadow, uv).rgb;

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

            float4 frag(v2f i) : SV_Target
            {
                float4 d = (_Denoise >= 3) ? SampleDeltaDenoised3x3(i.uv) : SampleDelta(i.uv);

                // RGB: extra reflected light (can be HDR). Keep >= 0.
                float3 extraLight = max(d.rgb * _LightScale, 0.0);

                // Alpha: 1 means no shadow, 0 means strong shadow.
                float shadowStrength = max(d.a * _ShadowScale, 0.0);
                float alpha = 1.0 - saturate(shadowStrength);

                return float4(extraLight, alpha);
            }
            ENDCG
        }
    }
}
