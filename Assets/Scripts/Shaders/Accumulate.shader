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

			#define _BufferLength 8

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

			sampler2D _MainTex;
			sampler2D _Frame01;
			sampler2D _Frame02;
			sampler2D _Frame03;
			sampler2D _Frame04;
			sampler2D _Frame05;
			sampler2D _Frame06;
			sampler2D _Frame07;
			sampler2D _Frame08;

			int _Frame;
			int _MaxFrames;

			float4 SampleFrame(int idx, float2 uv)
            {
                if (idx == 1) return tex2D(_Frame01, uv);
                if (idx == 2) return tex2D(_Frame02, uv);
                if (idx == 3) return tex2D(_Frame03, uv);
                if (idx == 4) return tex2D(_Frame04, uv);
                if (idx == 5) return tex2D(_Frame05, uv);
                if (idx == 6) return tex2D(_Frame06, uv);
                if (idx == 7) return tex2D(_Frame07, uv);
                return tex2D(_Frame08, uv);
            }

			float4 SampleColor3x3(float2 inUv, int _id)
			{
				float4 _Frame_TexelSize = float4(1.0 / 480, 1.0 / 270, 0, 0);   // x = 1/width, y = 1/height
				float2 texel = _Frame_TexelSize.xy;

				float _SigmaColor = 0.12;   // e.g. 0.12 (linear RGB)
				float _SigmaDepth = 1.0;    // e.g. 1.0  (same units as alpha distance)
				float _SigmaSpatial = 1.0;	// e.g. 1.0  (in pixels)

				float4 center = SampleFrame(_id, inUv);
				float3 cRgb = center.rgb;
				float  cD   = center.a;

				float sigmaC2 = max(_SigmaColor * _SigmaColor, 1e-8);
				float sigmaD2 = max(_SigmaDepth * _SigmaDepth, 1e-8);
				float sigmaS2 = max(_SigmaSpatial * _SigmaSpatial, 1e-8);

				float3 sumRgb = 0.0;
				float  sumA   = 0.0;
				float  sumW   = 0.0;

				// 3x3 kernel (change range to [-2..2] for 5x5)
				[unroll]
				for (int y = -1; y <= 1; y++)
				{
					[unroll]
					for (int x = -1; x <= 1; x++)
					{
						float2 uv = inUv + float2(x, y) * texel;
						float4 s = SampleFrame(_id, uv);

						// Spatial weight (keeps blur local)
						float r2 = (float)(x * x + y * y);
						float wS = exp(-r2 / (2.0 * sigmaS2));

						// Color similarity weight
						float3 dc = s.rgb - cRgb;
						float wC = exp(-dot(dc, dc) / (2.0 * sigmaC2));

						// Depth similarity weight + sky/geometry gating (assumes distance 0 means sky)
						float wD = 1.0;
						if (cD <= 0.0)
						{
							wD = (s.a <= 0.0) ? 1.0 : 0.0;
						}
						else
						{
							if (s.a <= 0.0) wD = 0.0;
							else
							{
								float dd = s.a - cD;
								wD = exp(-(dd * dd) / (2.0 * sigmaD2));
							}
						}

						float w = wS * wC * wD;

						sumRgb += s.rgb * w;
						sumA   += s.a * w;
						sumW   += w;
					}
				}

				if (sumW > 0.0)
					return float4(sumRgb / sumW, sumA / sumW);

				return center;
			}

			float4 frag (v2f i) : SV_Target
			{
				// ############################################################################
				// float4 accumulatedCol = float4(1,0,1,0); // Error magenta

				// // Safeguards
				// int maxFrames = clamp(_MaxFrames, 1, _BufferLength); // Clamps
				// int _frame = ((_Frame - 1) & (_BufferLength - 1)) + 1; // Ensures looping

				// for (int k = 0; k < maxFrames; k++)  
				// {
				// 	int frame = _frame - k;
				// 	if(frame < 1)
				// 	{
				// 		frame += _BufferLength;
				// 	}

				// 	float4 newCol = SampleFrame(frame, i.uv);
				// 	float weight = 1.0 / (k + 1);
				// 	accumulatedCol = lerp(accumulatedCol, newCol, weight);
				// }

				// // TEST Distance Debug
				// float d = SampleFrame(accumulatedCol, i.uv).a / 20.0; 
				// float4 col = float4(d,0,0,0);
				// return col;
				
				// OLD
				// This will clamp the final color to [0,1] range (removes HDR).
				// float4 finalCol = saturate(accumulatedCol);
				// return finalCol;

				// OLD
				// return accumulatedCol;
				// ############################################################################

				float4 accumulatedCol = float4(1,0,1,0); // Error magenta

				// // Safeguards
				int maxFrames = clamp(_MaxFrames, 1, _BufferLength); // Clamps
				int _frame = ((_Frame - 1) & (_BufferLength - 1)) + 1; // Ensures looping

				for (int k = 0; k < maxFrames; k++)  
				{
					int frame = _frame - k;
					if(frame < 1)
					{
						frame += _BufferLength;
					}

					float4 newCol;
					//newCol = SampleColor3x3(i.uv, frame);
					newCol = SampleFrame(frame, i.uv);
					// if(i.uv.y > 0.5)
					// {
					// 	newCol = SampleColor3x3(i.uv, frame);
					// }
					// else
					// {
					// 	newCol = SampleFrame(frame, i.uv);
					// }

					float weight = 1.0 / (k + 1);
					accumulatedCol = lerp(accumulatedCol, newCol, weight);
				}

				return accumulatedCol;
			}
			ENDCG
		}
	}
}
