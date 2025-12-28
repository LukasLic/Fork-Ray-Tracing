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

			#define MAX_POINT_LIGHTS 127
			#define MAX_BLOCKER_SEGMENTS 255

			 // Testing level values - really flat game.
			#define MAX_POS_Y 1.9
			#define MIN_POS_Y -100.0

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

			float Cross2(float2 a, float2 b)
			{
				return a.x * b.y - a.y * b.x;
			}

			bool IsNearlyParallel(float2 r, float2 s, float denom)
			{
				float denom2 = denom * denom;
				float rs2 = dot(r, r) * dot(s, s);
				return denom2 <= (1e-6 * rs2); // The parallel threshold in the world units squared
			}

			bool SegSegHit(float2 P, float2 L, float2 A, float2 B, out float3 debugCol)
			{
				float2 r = L - P;
				float2 s = B - A;

				float denom = Cross2(r, s);
				float2 AP = A - P;

				// Compute a small bias to avoid self-shadowing issues
				float shadowBiasWorld = 1e-3; // shadowBiasWorld is in world units
				float invLen = rsqrt(max(dot(r, r), 1e-10));
				float tEps = shadowBiasWorld * invLen;

				// Parallel case (including collinear)
				// 1: IsNearlyParallel(r, s, denom)
				// 2: abs(denom) < 1e-4
				if (IsNearlyParallel(r, s, denom))
				{
					// Consider every parallel case as a hit for now
					debugCol = float3(0.0, 0.0, 0.0);
					return true;

					// // If not collinear, no hit
					// if (abs(Cross2(AP, r)) > 1e-7) return false;

					// // Collinear: check overlap of projections onto r using t in [0,1]
					// float rr = dot(r, r); // Ray length squared
					// if (rr < 1e-10) return false; // Ray is at a point

					// float tA = dot(A - P, r) / rr;
					// float tB = dot(B - P, r) / rr;

					// float tMin = min(tA, tB);
					// float tMax = max(tA, tB);

					// // Any overlap with [0,1] counts as blocking
					// return (tMax >= 0.0) && (tMin <= 1.0);
				}

				// // float2 a = normalize(A2 - A1); // r
				// // float2 b = normalize(B2 - B1); // s
				// float angle = atan2(r.x * s.y - r.y * s.x, dot(r, s));
				// if(abs(angle) < 0.01)
				// {
				// 	debugCol = float3(0.0, 0.0, 1.0);
				// 	// return true;
				// }

				debugCol = float3(0.0, 0.0, 0.0);

				float t = Cross2(AP, s) / denom;
				float u = Cross2(AP, r) / denom;

				// Intersection within both segments
				return (t >= tEps) && (t <= 1.0) && (u >= 0.0) && (u <= 1.0);
			}

			// // Returns true if segments P->L and A->B intersect.
			// // If they do, hitPoint is the intersection point.
			// // For collinear overlap, hitPoint is the closest point on the overlap to P.
			// bool SegSegHitPoint(float2 P, float2 L, float2 A, float2 B, out float2 hitPoint)
			// {
			// 	float2 r = L - P;
			// 	float2 s = B - A;

			// 	float denom = Cross2(r, s);
			// 	float2 AP = A - P;

			// 	// Parallel (including collinear)
			// 	if (abs(denom) < 1e-7)
			// 	{
			// 		// Not collinear
			// 		if (abs(Cross2(AP, r)) > 1e-7)
			// 		{
			// 			hitPoint = 0;
			// 			return false;
			// 		}

			// 		float rr = dot(r, r);
			// 		if (rr < 1e-10)
			// 		{
			// 			hitPoint = 0;
			// 			return false;
			// 		}

			// 		// Project A and B onto ray to get overlap in t
			// 		float tA = dot(A - P, r) / rr;
			// 		float tB = dot(B - P, r) / rr;

			// 		float tMin = min(tA, tB);
			// 		float tMax = max(tA, tB);

			// 		// Overlap with [0,1] ?
			// 		if (tMax < 0.0 || tMin > 1.0)
			// 		{
			// 			hitPoint = 0;
			// 			return false;
			// 		}

			// 		// Closest point on overlap interval to P (t = 0)
			// 		float tHit = max(tMin, 0.0);
			// 		tHit = min(tHit, 1.0);

			// 		hitPoint = P + r * tHit;
			// 		return true;
			// 	}

			// 	float t = Cross2(AP, s) / denom;
			// 	float u = Cross2(AP, r) / denom;

			// 	if (t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0)
			// 	{
			// 		hitPoint = P + r * t;
			// 		return true;
			// 	}

			// 	hitPoint = 0;
			// 	return false;
			// }

			sampler2D _CameraColor;
			sampler2D _CameraWorldPositions;

			int BlockerSegmentCount;
			StructuredBuffer<float4> BlockerSegments;    // xy = start, zw = end

			int PointLightCount;
			StructuredBuffer<float4> PointLights; // xy = position, z = radius, w = intensity

			float4 frag(v2f i) : SV_Target
			{
				float3 pixelColor =	tex2D(_CameraColor, i.uv).rgb;
				float3 pixelWorldPos3 =	tex2D(_CameraWorldPositions, i.uv).rgb;
				float2 worldPos = float2(pixelWorldPos3.x, pixelWorldPos3.z);

				// Pixel is too high or too low, discard.
				if(pixelWorldPos3.y < MIN_POS_Y || pixelWorldPos3.y > MAX_POS_Y) // TODO Make configurable and do a smooth transition.
				{
					return float4(0.0, 0.0, 0.0, 1.0);
				}

				float l = 0.0;

				[loop]
				for (int j = 0; j < MAX_POINT_LIGHTS; j++)
				{
					if(j >= PointLightCount) break;

					float4 light = PointLights[j];
					float d = distance(worldPos, light.xy);
					float atten = PointLightAtten_Smooth(d, light.z, light.w);

					if (atten <= 0.0) continue;

					// Check for blockers
					[loop]
					for (int s = 0; s < MAX_BLOCKER_SEGMENTS; s++)
					{
						if (s >= BlockerSegmentCount) break;

						float4 segment = BlockerSegments[s];
						float2 _A = segment.xy;
						float2 _B = segment.zw;

						float2 toLight  = light.xy - worldPos;
						float toLightDot = dot(toLight, toLight);

						// Cheap projection gate
						// Keep only blockers that overlap the slab between worldPos (t=0) and light.xy (t=1)
						float pa = dot(_A - worldPos, toLight);
						float pb = dot(_B - worldPos, toLight);
						if (max(pa, pb) <= 0.0) continue; // both points behind worldPos
						if (min(pa, pb) >= toLightDot)  continue; // both points beyond light.xy

						// Optional AABB gate
						// (The lines form a bounding box, so if the boxes don't overlap, no intersection is possible)
						float2 segMin = min(_A, _B);
						float2 segMax = max(_A, _B);
						float2 rayMin = min(worldPos, light.xy);
						float2 rayMax = max(worldPos, light.xy);
						if (segMax.x < rayMin.x || segMin.x > rayMax.x ||
							segMax.y < rayMin.y || segMin.y > rayMax.y) continue;

						// TODO: Move the worldPos a bit towards the light to avoid self-shadowing issues.
						float2 worldPosC = worldPos + normalize(light.xy - worldPos) * 1e-3;

						// Full 2D line segment intersection test
						// Exact test
						float3 debugCol;
						if (SegSegHit(worldPosC, light.xy, _A, _B, debugCol))
						{
							// return float4(debugCol, 1.0);
							atten = 0.0;
							break;
						}
					}

					l += atten;
				}

				return float4(pixelColor * saturate(l), 1.0);
			}

			ENDCG
		}
	}
}
