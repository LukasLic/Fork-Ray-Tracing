Shader "Custom/RayTracer"
{
	SubShader
	{
		Cull Off 
		ZWrite Off
		ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0
			#include "UnityCG.cginc"

			#define MAX_POINT_LIGHTS 128

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

			float PointLightAtten_Smooth(float d, float radius, float intensity)
			{
				float t = saturate(1.0 - d / radius);
				return intensity * t * t; // quadratic falloff
			}

			sampler2D _CameraColor;
			sampler2D _CameraWorldPositions;

			int PointLightCount;
			StructuredBuffer<float4> PointLights; // xy = position, z = radius, w = intensity

			float4 frag(v2f i) : SV_Target
			{
				float3 pixelColor =	tex2D(_CameraColor, i.uv).rgb;
				float3 pixelWorldPos3 =	tex2D(_CameraWorldPositions, i.uv).rgb;
				float2 worldPos = float2(pixelWorldPos3.x, pixelWorldPos3.z);

				float l = 0.0;

				[loop]
				for (int j = 0; j < MAX_POINT_LIGHTS; j++)
				{
					if(j >= PointLightCount) break;

					float4 light = PointLights[j];

					float d = distance(worldPos, light.xy);

					l += PointLightAtten_Smooth(d, light.z, light.w);
				}

				return float4(pixelColor * saturate(l), 1.0);
			}

			ENDCG
		}
	}
}
