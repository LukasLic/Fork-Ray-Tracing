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

			// DX11 shader model 5.0.
			// Not supported on DX11 before SM5.0, OpenGL before 4.3 (i.e. Mac), OpenGL ES 2.0/3.0/3.1, Metal.
			// Supported on DX11+ SM5.0, OpenGL 4.3+, OpenGL ES 3.1+AEP, Vulkan, Metal (without geometry), PS4/XB1 consoles.
			#pragma target 5.0

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

			RWTexture2D<uint> _FrameCountUAV : register(u1);

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
						//return float4(1,0,0, 0); // Debug red for no hit yet.
						return float4(0,0,0, 0);
					}
					// ...else return previous frame color (don't update by misses).
					else
					{
						return colPrev;
					}
				}

				// Get the pixel for the _FrameCountUAV access.
				uint2 size = (uint2)_ScreenParams.xy;
				uint2 pix = (uint2)(i.uv * size);
				pix = min(pix, size - 1);

				// If this is the first valid hit frame, throw away the previous debug red.
				if(colPrev.a == 0)
				{
					uint _oldValue;
					InterlockedExchange(_FrameCountUAV[pix], 1u, _oldValue); // Set frame count to 1.
					return col;
				}

				// uint _frame = _Frame;
				// FIXME: Make one distance texture and one RGB texture, where Alpha is the next image weight.
				// This will fix, the behaviour where the random chance picks a color, but picks it too late, so the weight is negligible.
				
				uint _frame = 1;
				InterlockedAdd(_FrameCountUAV[pix], 1, _frame);
				
				float p = 3;
				float weight = (p + 1) / (p + _frame);

				// Combine prev frame with current frame. Weight the contributions to result in an average over all frames.
				// If weight is 1, only current frame is used.
				// As the weight decreses, previous frames contribute more.
				float4 accumulatedCol = saturate(colPrev * (1 - weight) + col * weight); // Saturate to avoid HDR issues (for ex. too bright sun).
				
				// Also accumulate distance in alpha channel.
				// Be careful, as the value ranges my be extreme, causing issues later in the pipeline.
				accumulatedCol.a = colPrev.a * (1 - weight) + col.a * weight;

				// // Debug
				// accumulatedCol.a = (float)_frame;

				return accumulatedCol;
			}
			ENDCG
		}
	}
}
