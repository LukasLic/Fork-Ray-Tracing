Shader "Hidden/Compose"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
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
			

			float4 frag (v2f i) : SV_Target
			{
				float3 final = float3(0,0,0);
				float4 s01 = tex2D(_Snapshot01, i.uv);

				// TODO: Compose the snapshots together as needed.
				final = s01.rgb;

				return float4(saturate(final), 0);
			}
			ENDCG
		}
	}
}
