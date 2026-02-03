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
				if(_Accumulate == 0 || _Frame == 0) 
				{
					return saturate(tex2D(_MainTex, i.uv));
				}

				float weight = 0.5f;
				float4 sample = tex2D(_MainTex, i.uv);
				float4 prev = tex2D(_PrevFrame, i.uv);
				// ///////////////////////////////////////////////////////////////
				// ///////////////////////////////////////////////////////////////
				if(_Frame < 10) // First ten frames, simple add for 10th frame average
				{
					return prev + saturate(sample); 
				}
				if(_Frame == 10) // Average of first ten frames
				{
					float avgWeight = 1.0 / 10.0;
					float4 tenthFrame = prev + saturate(sample);
					return tenthFrame * avgWeight;
				}

				// After ten frames, do a weighted blend to slowly converge.
				int offset = 4 * 10; // Offset to account for the first ten frames being added directly.
				weight = 1.0 / (float)(
					((_Frame + offset) / 4.0)
					+ 1
				);
				// weight = 1.0 / (float)(_Frame);
				return lerp(prev, sample, weight);
				// ///////////////////////////////////////////////////////////////
				// ///////////////////////////////////////////////////////////////
				float3 prevRgb   = prev.rgb;
				float3 sampleRgb = sample.rgb;

				// HDR luminance (Rec.709)
				float prevLum   = dot(prevRgb,   float3(0.2126, 0.7152, 0.0722));
				float sampleLum = dot(sampleRgb, float3(0.2126, 0.7152, 0.0722));

				if (sampleLum > prevLum)
				{
					weight = 0.8f;
					return lerp(prev, sample, weight);
				}
				else
				{
					weight = 1.0 / (float)(_Frame + 1);
					// float3 _new = prev + (sample - prev) * weight;
					// return lerp(prev, _new, weight);
					return lerp(prev, sample, weight);
				}

				// // return lerp(prev, sample, 0.45);

				// // _Frame should be 0 on the first accumulated frame after a reset/clear.
				// float weight = 0.5f;
				// if (_Frame < 10)
				// {
				// 	return lerp(prev, sample, 0.45); // constant blend factor
				// }
				// else if(_Frame < 300)
				// {
				// 	int __frame = (_Frame / 2) + 5;
				// 	weight = 1.0 / (float)(__frame + 1);
				// 	return prev + (sample - prev) * weight; // simple weight over time
				// }
				// else
				// {
				// 	weight = 1.0 / (float)(_Frame + 1);
				// 	return prev + (sample - prev) * weight;
				// }
				
				// return lerp(prev, sample, 0.05); // constant blend factor
				// ///////////////////////////////////////////////////////////////
				// ///////////////////////////////////////////////////////////////

				// // if(_ClearFrameCount == 0)
				// // {

				// // 	return float4(0,0,0,0);
				// // }

				// float4 col = tex2D(_MainTex, i.uv);
				// float4 colPrev = tex2D(_PrevFrame, i.uv);

				// // If this frame was not a hit...
				// if(col.a == 0)
				// {
				// 	// ...and previous frame was also not a hit, return a debug color (red).
				// 	if(colPrev.a == 0)
				// 	{
				// 		return float4(1,0,0, 0); // Debug red for no hit yet.
				// 		// return float4(0,0,0, 0);
				// 	}
				// 	// ...else return previous frame color (don't update by misses).
				// 	else
				// 	{
				// 		return colPrev;
				// 	}
				// }

				// // If this is the first valid hit frame, throw away the previous debug red.
				// if(colPrev.a == 0)
				// {
				// 	return col;
				// }

				// // FIXME: Make one distance texture and one RGB texture, where Alpha is the next image weight.
				// // This will fix, the behaviour where the random chance picks a color, but too late, so the weight is negligible.

				// // float dst = col.a;
				// // float dstPrev = colPrev.a;

				// float weight = 1.0 / (_Frame + 1);
				// // Combine prev frame with current frame. Weight the contributions to result in an average over all frames.
				// // float4 accumulatedCol = saturate(colPrev * (1 - weight) + col * weight); // Saturate to avoid HDR issues (for ex. too bright sun).
				
				// float4 accumulatedCol = colPrev * (1 - weight) + col * weight;
				
				// //accumulatedCol.a = dst * weight + dstPrev * (1 - weight); // Accumulate distance in alpha channel.

				// return accumulatedCol;
			}
			ENDCG
		}
	}
}
