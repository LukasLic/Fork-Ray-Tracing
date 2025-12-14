Shader "Hidden/Accumulate"
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

			// RWTexture2D<uint> _FrameCountUAV : register(u1);

			sampler2D _MainTex;
			sampler2D _PrevFrame;
			int _Frame;
			int _Accumulate;
			int _ClearFrameCount;

			float4 frag (v2f i) : SV_Target
			{
				if(_Accumulate == 0) 
				{
					return tex2D(_MainTex, i.uv);
				}

				// if(_ClearFrameCount == 0)
				// {

				// 	return float4(0,0,0,0);
				// }

				float4 col = tex2D(_MainTex, i.uv);
				float4 colPrev = tex2D(_PrevFrame, i.uv);

				// If this frame was not a hit...
				if(col.a == 0)
				{
					// ...and previous frame was also not a hit, return a debug color (red).
					if(colPrev.a == 0)
					{
						return float4(1,0,0, 0); // Debug red for no hit yet.
						// return float4(0,0,0, 0);
					}
					// ...else return previous frame color (don't update by misses).
					else
					{
						colPrev;
					}
				}

				// If this is the first valid hit frame, throw away the previous debug red.
				if(colPrev.a == 0)
				{
					return col;
				}

				// FIXME: Make one distance texture and one RGB texture, where Alpha is the next image weight.
				// This will fix, the behaviour where the random chance picks a color, but too late, so the weight is negligible.

				// float dst = col.a;
				// float dstPrev = colPrev.a;

				float weight = 1.0 / (_Frame + 1);
				// Combine prev frame with current frame. Weight the contributions to result in an average over all frames.
				float4 accumulatedCol = saturate(colPrev * (1 - weight) + col * weight); // Saturate to avoid HDR issues (for ex. too bright sun).
				//float4 accumulatedCol = colPrev * (1 - weight) + col * weight;
				
				//accumulatedCol.a = dst * weight + dstPrev * (1 - weight); // Accumulate distance in alpha channel.

				return accumulatedCol;
			}
			ENDCG
		}
	}
}
