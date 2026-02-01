Shader "Custom/RayTracer"
{
	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			UNITY_DECLARE_TEX2DARRAY(_NormalMaps);

			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			#pragma multi_compile _ DEBUG_VIS
			#pragma target 4.5

			#define MAX_DISTANCE 5000.0
			#define NO_HIT 0.0

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

			// --- Settings and constants ---
			static const float PI = 3.1415;

			// Raytracing Settings
			int MaxBounceCount;
			int NumRaysPerPixel;
			int Frame;

			// Camera settings
			float DefocusStrength;
			float DivergeStrength;
			float3 ViewParams;
			float4x4 CamLocalToWorldMatrix;

			// Sky settings
			int UseSky;
			float3 SunColour;
			float SunFocus = 500;
			float SunIntensity = 10;

			// Debug settings
			int visMode;
			float debugVisScale;

			// --- Structures ---
			struct Ray
			{
				float3 origin;
				float3 dir;
				float3 invDir;
			};

			struct Triangle
			{
				float3 posA, posB, posC;
				float3 normA, normB, normC;

				float2 uvA, uvB, uvC;
				float4 tanA, tanB, tanC; // xyz = tangent, w = handedness
			};

			struct TriangleHitInfo
			{
				bool didHit;
				float dst;
				float3 hitPoint;
				float3 normal; // interpolated vertex normal (local)
				int triIndex;
				float3 bary;     // (w,u,v)
				Triangle tri;
			};

			struct RayTracingMaterial
			{
				float4 colour;
				float4 emissionColour;
				float4 specularColour;
				float emissionStrength;
				float smoothness;
				float specularProbability;
				int flag;

				int normalScale;    // typical 1
				int normalMapIndex;   // -1 = none
				float4 uvST;          // xy = scale, zw = offset
			};

			struct Model
			{
				int nodeOffset;
				int triOffset;
				float4x4 worldToLocalMatrix;
				float4x4 localToWorldMatrix;
				RayTracingMaterial material;
			};

			struct BVHNode
			{
				float3 boundsMin;
				float3 boundsMax;
				// index refers to triangles if is leaf node (triangleCount > 0)
				// otherwise it is the index of the first child node
				int startIndex;
				int triangleCount;
			};

			struct ModelHitInfo
			{
				bool didHit;
			    float3 normal;      // shading normal (world) - includes normal map
				float3 geoNormal;   // geometric normal (world) - use for ray offset
				float3 hitPoint;
				float dst;
				RayTracingMaterial material;
			};

			// --- Buffers (and their sizes) ---	
			StructuredBuffer<Model> ModelInfo;
			StructuredBuffer<Triangle> Triangles;
			StructuredBuffer<BVHNode> Nodes;
			int triangleCount;
			int modelCount;

			// ---- RNG Functions ----

			// PCG (permuted congruential generator). Thanks to:
			// www.pcg-random.org and www.shadertoy.com/view/XlGcRh
			uint NextRandom(inout uint state)
			{
				state = state * 747796405 + 2891336453;
				uint result = ((state >> ((state >> 28) + 4)) ^ state) * 277803737;
				result = (result >> 22) ^ result;
				return result;
			}

			float RandomValue(inout uint state)
			{
				return NextRandom(state) / 4294967295.0; // 2^32 - 1
			}

			// Random value in normal distribution (with mean=0 and sd=1)
			float RandomValueNormalDistribution(inout uint state)
			{
				// Thanks to https://stackoverflow.com/a/6178290
				float theta = 2 * 3.1415926 * RandomValue(state);
				float rho = sqrt(-2 * log(RandomValue(state)));
				return rho * cos(theta);
			}

			// Calculate a random direction
			float3 RandomDirection(inout uint state)
			{
				// Thanks to https://math.stackexchange.com/a/1585996
				float x = RandomValueNormalDistribution(state);
				float y = RandomValueNormalDistribution(state);
				float z = RandomValueNormalDistribution(state);
				return normalize(float3(x, y, z));
			}

			float2 RandomPointInCircle(inout uint rngState)
			{
				float angle = RandomValue(rngState) * 2 * PI;
				float2 pointOnCircle = float2(cos(angle), sin(angle));
				return pointOnCircle * sqrt(RandomValue(rngState));
			}

			// Crude sky colour function for background light
			float3 GetEnvironmentLight(float3 dir)
			{
				if (UseSky == 0)
				{
					float3 sunDir = normalize(_WorldSpaceLightPos0.xyz);
					float  cosAng = dot(normalize(dir), sunDir);

					// Hard cutoff for "pitch black unless looking close to the sun"
					// Tune these two to control sun size and edge softness.
					const float SunDiskCos = 0.9995;   // closer to 1 = smaller disc
					const float SunEdgeSoft = 0.0003;  // smaller = sharper edge

					float sunMask = smoothstep(SunDiskCos - SunEdgeSoft, SunDiskCos, cosAng);
					float sunCore = pow(saturate(cosAng), SunFocus) * SunIntensity;

					return SunColour * (sunCore * sunMask);
				}
				const float3 GroundColour = float3(0.35, 0.3, 0.35);
				const float3 SkyColourHorizon = float3(1, 1, 1);
				const float3 SkyColourZenith = float3(0.08, 0.37, 0.73);
				

				float skyGradientT = pow(smoothstep(0, 0.4, dir.y), 0.35);
				float groundToSkyT = smoothstep(-0.01, 0, dir.y);
				float3 skyGradient = lerp(SkyColourHorizon, SkyColourZenith, skyGradientT);
				float sun = pow(max(0, dot(dir, _WorldSpaceLightPos0.xyz)), SunFocus) * SunIntensity; // TODO
				// Combine ground, sky, and sun
				float3 background = lerp(GroundColour, skyGradient, groundToSkyT);
				float3 composite = background * 99.0 + sun * SunColour * (groundToSkyT >= 1);
				// float3 composite = lerp(GroundColour, skyGradient, groundToSkyT);
				return composite;
			}

			// --- Ray Intersection Functions ---

			// Build an orthonormal basis (tangent, bitangent) from a unit normal n.
			// Frisvad 2012, branchless and no normalize needed if n is normalized.
			void BuildONB_Frisvad(float3 n, out float3 t, out float3 b)
			{
				float sign_ = (n.z >= 0.0) ? 1.0 : -1.0;
				float a = -1.0 / (sign_ + n.z);
				float bxy = n.x * n.y * a;

				t = float3(1.0 + sign_ * n.x * n.x * a, sign_ * bxy, -sign_ * n.x);
				b = float3(bxy, sign_ + n.y * n.y * a, -n.y);
			}

			// Cosine-weighted hemisphere sample around normal n (n must be normalized)
			float3 CosineSampleHemisphereFast(float3 n, inout uint rngState)
			{
				float u1 = RandomValue(rngState);
				float u2 = RandomValue(rngState);

				float phi = 2.0 * PI * u1;

				float s, c;
				sincos(phi, s, c);

				float r = sqrt(u2);
				float x = r * c;
				float y = r * s;
				float z = sqrt(1.0 - u2);

				float3 t, b;
				BuildONB_Frisvad(n, t, b);

				return t * x + b * y + n * z;
			}

			// Calculate the intersection of a ray with a triangle using Möller–Trumbore algorithm
			// Thanks to https://stackoverflow.com/a/42752998
			TriangleHitInfo RayTriangle(Ray ray, Triangle tri)
			{
				float3 edgeAB = tri.posB - tri.posA;
				float3 edgeAC = tri.posC - tri.posA;
				float3 normalVector = cross(edgeAB, edgeAC);
				float3 ao = ray.origin - tri.posA;
				float3 dao = cross(ao, ray.dir);

				float determinant = -dot(ray.dir, normalVector);
				float invDet = 1 / determinant;

				// Calculate dst to triangle & barycentric coordinates of intersection point
				float dst = dot(ao, normalVector) * invDet;
				float u = dot(edgeAC, dao) * invDet;
				float v = -dot(edgeAB, dao) * invDet;
				float w = 1 - u - v;

				// Initialize hit info
				TriangleHitInfo hitInfo;
				hitInfo.didHit = determinant >= 1E-8 && dst >= 0 && u >= 0 && v >= 0 && w >= 0;
				hitInfo.hitPoint = ray.origin + ray.dir * dst;
				hitInfo.normal = normalize(tri.normA * w + tri.normB * u + tri.normC * v);
				hitInfo.dst = dst;
				hitInfo.bary = float3(w, u, v);
				hitInfo.tri = tri;
				return hitInfo;
			}

			// Thanks to https://tavianator.com/2011/ray_box.html
			float RayBoundingBoxDst(Ray ray, float3 boxMin, float3 boxMax)
			{
				float3 tMin = (boxMin - ray.origin) * ray.invDir;
				float3 tMax = (boxMax - ray.origin) * ray.invDir;
				float3 t1 = min(tMin, tMax);
				float3 t2 = max(tMin, tMax);
				float tNear = max(max(t1.x, t1.y), t1.z);
				float tFar = min(min(t2.x, t2.y), t2.z);

				bool hit = tFar >= tNear && tFar > 0;
				float dst = hit ? tNear > 0 ? tNear : 0 : 1.#INF;
				return dst;
			};


			TriangleHitInfo RayTriangleBVH(inout Ray ray, float rayLength, int nodeOffset, int triOffset, inout int2 stats)
			{
				TriangleHitInfo result;
				result.didHit = false;
				result.dst = rayLength;
				result.hitPoint = 0;
				result.normal = 0;
				result.triIndex = -1;
				result.bary = 0;

				int stack[32];
				int stackIndex = 0;
				stack[stackIndex++] = nodeOffset + 0;

				while (stackIndex > 0)
				{
					BVHNode node = Nodes[stack[--stackIndex]];
					bool isLeaf = node.triangleCount > 0;

					if (isLeaf)
					{
						for (int i = 0; i < node.triangleCount; i++)
						{
							Triangle tri = Triangles[triOffset + node.startIndex + i];
							TriangleHitInfo triHitInfo = RayTriangle(ray, tri);
							stats[0]++; // count triangle intersection tests

							if (triHitInfo.didHit && triHitInfo.dst < result.dst)
							{
								result = triHitInfo;
								result.triIndex = node.startIndex + i;
								result.didHit = true;
							}
						}
					}
					else
					{
						int childIndexA = nodeOffset + node.startIndex + 0;
						int childIndexB = nodeOffset + node.startIndex + 1;
						BVHNode childA = Nodes[childIndexA];
						BVHNode childB = Nodes[childIndexB];

						float dstA = RayBoundingBoxDst(ray, childA.boundsMin, childA.boundsMax);
						float dstB = RayBoundingBoxDst(ray, childB.boundsMin, childB.boundsMax);
						stats[1] += 2; // count bounding box intersection tests
						
						// We want to look at closest child node first, so push it last
						bool isNearestA = dstA <= dstB;
						float dstNear = isNearestA ? dstA : dstB;
						float dstFar = isNearestA ? dstB : dstA;
						int childIndexNear = isNearestA ? childIndexA : childIndexB;
						int childIndexFar = isNearestA ? childIndexB : childIndexA;

						if (dstFar < result.dst) stack[stackIndex++] = childIndexFar;
						if (dstNear < result.dst) stack[stackIndex++] = childIndexNear;
					}
				}


				return result;
			}

			// Encapsulates "Record closest hit" including normal-map shading normal.
			// Call this only when (hit.didHit && hit.dst < result.dst) is already true.
			void RecordClosestHit(
				in Ray worldRay,
				in Model model,
				in TriangleHitInfo hit,
				inout ModelHitInfo result)
			{
				result.didHit = true;
				result.dst = hit.dst;
				result.hitPoint = worldRay.origin + worldRay.dir * hit.dst;
				result.material = model.material;

				// Base world normal from vertex normals
				float3 nW = normalize(mul(model.localToWorldMatrix, float4(hit.normal, 0)).xyz);
				float3 shadingN = nW;

				// Normal map (tangent space -> world)
				if (result.material.normalMapIndex >= 0)
				{
					Triangle tri = Triangles[model.triOffset + hit.triIndex];
					hit.tri = tri;

					float w = hit.bary.x;
					float u = hit.bary.y;
					float v = hit.bary.z;

					// Interpolated UV with scale/offset
					float2 uv = tri.uvA * w + tri.uvB * u + tri.uvB * 0 + tri.uvC * v; // keep structure similar
					uv = tri.uvA * w + tri.uvB * u + tri.uvC * v;
					uv = uv * result.material.uvST.xy + result.material.uvST.zw;

					// Interpolated tangent (local -> world)
					float4 tanL = tri.tanA * w + tri.tanB * u + tri.tanC * v;
					float3 tW_raw = mul(model.localToWorldMatrix, float4(tanL.xyz, 0)).xyz;

					float3 tW, bW;
					if (dot(tW_raw, tW_raw) < 1e-8)
					{
						// Fallback basis if tangent is missing/degenerate
						BuildONB_Frisvad(nW, tW, bW);
					}
					else
					{
						tW = normalize(tW_raw);
						tW = normalize(tW - nW * dot(nW, tW)); // orthonormalize
						bW = cross(nW, tW) * tanL.w;           // handedness in w
					}

					// Sample normal map at LOD 0 (ray tracer has no screen-space derivatives)
					// float3 packed = SAMPLE_TEXTURE2D_ARRAY_LOD(
					// 	_NormalMaps, sampler_NormalMaps[result.material.normalMapIndex], float3(uv, 0), 0
					// ).xyz;
					float slice = (float)result.material.normalMapIndex;

					// HERE - NORMAL
					// float3 packed = UNITY_SAMPLE_TEX2DARRAY_LOD(_NormalMaps, float3(uv, slice), 0).xyz;
					// float3 nTS = packed * 2.0 - 1.0; // Unpack tangent-space normal
					// ////////////////////
					float4 packed = UNITY_SAMPLE_TEX2DARRAY_LOD(_NormalMaps, float3(uv, slice), 0);
					float3 nTS = UnpackNormal(packed);
					nTS.xy *= result.material.normalScale;
					nTS = normalize(nTS);
					// ////////////////////


					// nTS.xy *= result.material.normalScale; // Assume 1 for now
					nTS.xy *= sqrt(result.material.normalScale);
					nTS = normalize(nTS);

					shadingN = normalize(tW * nTS.x + bW * nTS.y + nW * nTS.z);
				}

				// Keep shading normal facing the incoming ray (more stable)
				if (dot(shadingN, -worldRay.dir) < 0) shadingN = -shadingN;

				result.geoNormal = nW;
				result.normal = shadingN;
			}


			ModelHitInfo CalculateRayCollision(Ray worldRay, int bounce, out int2 stats, out TriangleHitInfo triHit)
			{
				stats = 0;
				ModelHitInfo result;
				result.didHit = false;
				result.dst = 1.#INF;
				result.hitPoint = 0;
				result.normal = 0;
				Ray localRay;

				for (int i = 0; i < modelCount; i++)
				{
					Model model = ModelInfo[i];

					// FIXME: InvisibleLight materials can still bounce subsequent rays into wrong directions.
					// We should add the emisssion light, but continue traversing the ray.
					if(model.material.flag == 2 && bounce == 0) // InvisibleLight
					{
						// TODO: Add emission pass info
						continue;
					}

					// Transform ray into model's local coordinate space
					localRay.origin = mul(model.worldToLocalMatrix, float4(worldRay.origin, 1));
					localRay.dir = mul(model.worldToLocalMatrix, float4(worldRay.dir, 0));
					localRay.invDir = 1 / localRay.dir;

					// Traverse bvh to find closest triangle intersection with current model
					TriangleHitInfo hit = RayTriangleBVH(localRay, result.dst, model.nodeOffset, model.triOffset, stats);

					// Record closest hit
					if (hit.didHit && hit.dst < result.dst)
					{
						triHit = hit;
						RecordClosestHit(worldRay, model, hit, result);
					}

					// TODO: Apply the emission pass here.
				}

				return result;
			}

			float2 mod2(float2 x, float2 y)
			{
				return x - y * floor(x / y);
			}

			float3 Trace(float3 rayOrigin, float3 rayDir, inout uint rngState, out float firstRayDst)
			{
				firstRayDst = NO_HIT;

				float3 incomingLight = 0;
				float3 rayColour = 1;
				
				int2 stats;
				TriangleHitInfo triHit;
				float dstSum = 0;

				for (int bounceIndex = 0; bounceIndex < MaxBounceCount; bounceIndex++)
				{
					Ray ray;
					ray.origin = rayOrigin;
					ray.dir = rayDir;
					ModelHitInfo hitInfo = CalculateRayCollision(ray, bounceIndex, stats, triHit);

					if (hitInfo.didHit)
					{
						if (bounceIndex == 0) // First hit only
						{
							firstRayDst = length(hitInfo.hitPoint - _WorldSpaceCameraPos);
						}

						dstSum += hitInfo.dst;
						RayTracingMaterial material = hitInfo.material;
						if (material.flag == 1) // Checker pattern
						{
							float2 c = mod2(floor(hitInfo.hitPoint.xz), 2.0);
							material.colour = c.x == c.y ? material.colour : material.emissionColour;
						}

						// Figure out new ray position and direction
						bool isSpecularBounce = material.specularProbability >= RandomValue(rngState);

						// Offset to avoid self-hit speckles
						// rayOrigin = hitInfo.hitPoint + hitInfo.normal * 1e-4;
						rayOrigin = hitInfo.hitPoint + hitInfo.geoNormal * 1e-4;

						// /////////////////////////////////////////////////////////////
						// Apply distance absorption for the segment we just traveled
						if(bounceIndex > 0 && hitInfo.didHit && hitInfo.material.flag == 2)
						{
							// float AirAbsorption = 0.155; // tune
							float BounceAbsorption = 0.275; // tune
							// rayColour *= exp(-AirAbsorption * hitInfo.dst);
							rayColour *= exp(-BounceAbsorption * bounceIndex * bounceIndex);
							// rayColour *= (1.0 / bounceIndex);
						}
						// /////////////////////////////////////////////////////////////

						// Figure out new ray direction
						// float3 diffuseDir = normalize(hitInfo.normal + RandomDirection(rngState));
						float3 diffuseDir = CosineSampleHemisphereFast(hitInfo.normal, rngState); // TODO: This should be a bit quicker

						float3 specularDir = reflect(rayDir, hitInfo.normal);
						rayDir = normalize(lerp(diffuseDir, specularDir, material.smoothness * isSpecularBounce));

						// Update light calculations
						float3 emittedLight = material.emissionColour * material.emissionStrength;
						incomingLight += emittedLight * rayColour;
						rayColour *= lerp(material.colour, material.specularColour, isSpecularBounce);

						// End early when hitting emission surface
						if(bounceIndex > 0 && hitInfo.didHit && hitInfo.material.flag == 2)
						{
							break;
						}
						// Random early exit if ray colour is nearly 0 (can't contribute much to final result)
						// float p = max(rayColour.r, max(rayColour.g, rayColour.b));
						float p = dot(saturate(rayColour), float3(0.2126, 0.7152, 0.0722));
						if ((RandomValue(rngState) * 1.0) >= p) {
							break;
						}
						rayColour *= 1.0f / p;
					}
					else
					{
						if(bounceIndex > 0)
						{
							float BounceAbsorption = 0.365; // tune
							rayColour *= exp(-BounceAbsorption * bounceIndex);
						}
						incomingLight += GetEnvironmentLight(rayDir) * rayColour;
						break;
					}
				}

				return incomingLight;
			}


			float3 TraceDebugMode(float3 rayOrigin, float3 rayDir)
			{
				int2 stats; // num triangle tests, num bounding box tests
				Ray ray;
				ray.origin = rayOrigin;
				ray.dir = rayDir;
				TriangleHitInfo triHit;
				ModelHitInfo hitInfo = CalculateRayCollision(ray, 0, stats, triHit);

				// Triangle test count vis
				if (visMode == 1)
				{
					float triVis = stats[0] / debugVisScale;
					return triVis < 1 ? triVis : float3(1, 0, 0);
				}
				// Box test count vis
				else if (visMode == 2)//
				{
					float boxVis = stats[1] / debugVisScale;
					return boxVis < 1 ? boxVis : float3(1, 0, 0);
				}
				// Distance
				else if (visMode == 3)
				{
					return length(rayOrigin - hitInfo.hitPoint) / debugVisScale;
				}
				// Normal
				else if (visMode == 4)
				{
					// hitInfo

					if (!hitInfo.didHit) return 0;

					// float s = triHit.bary.x + triHit.bary.y + triHit.bary.z;
					// return float3(s, s, s); // should be almost white (1.0)
					Triangle tri = triHit.tri;
					RayTracingMaterial resultMaterial = hitInfo.material;

					float w = triHit.bary.x;
					float u = triHit.bary.y;
					float v = triHit.bary.z;

					// Interpolated UV with scale/offset
					float2 uv = tri.uvA * w + tri.uvB * u + tri.uvB * 0 + tri.uvC * v; // keep structure similar
					uv = tri.uvA * w + tri.uvB * u + tri.uvC * v;
					uv = uv * resultMaterial.uvST.xy + resultMaterial.uvST.zw;

					// return (resultMaterial.normalMapIndex + 1.0) / 8.0;

					float slice = (float)resultMaterial.normalMapIndex;
					float3 packed = UNITY_SAMPLE_TEX2DARRAY_LOD(_NormalMaps, float3(uv, slice), 0).xyz;

					if(resultMaterial.normalMapIndex >= 0)
					{
						return packed;
					}
					return float3(0, 0, 0);

					// return float3(uv, 0);

					// return triHit.bary * float3(1, 1, 1);
					// return hitInfo.normal * 0.5 + 0.5;
				}

				return float3(1, 0, 1); // Invalid test mode
			}


			// Run for every pixel in the display
			float4 frag(v2f i) : SV_Target
			{
				// Create seed for random number generator
				uint2 numPixels = _ScreenParams.xy;
				uint2 pixelCoord = i.uv * numPixels;
				uint pixelIndex = pixelCoord.y * numPixels.x + pixelCoord.x;
				uint rngState = pixelIndex + Frame * 719393;//

				// Calculate focus point
				float3 focusPointLocal = float3(i.uv - 0.5, 1) * ViewParams;
				float3 focusPoint = mul(CamLocalToWorldMatrix, float4(focusPointLocal, 1));
				float3 camRight = CamLocalToWorldMatrix._m00_m10_m20;
				float3 camUp = CamLocalToWorldMatrix._m01_m11_m21;

				// Debug Mode
				#if DEBUG_VIS
					return float4(TraceDebugMode(_WorldSpaceCameraPos, normalize(focusPoint - _WorldSpaceCameraPos)), 1);
				#endif
				
				// Trace multiple rays and average together
				float3 totalIncomingLight = 0;
				// Distance averaging
				float distSum = 0.0;
				int distCount = 0;

				// if(RandomValue(rngState) > 0.25f) // TODO: Configurable
				// {
				// 	return float4(0,0,0, 0);
				// }

				for (int rayIndex = 0; rayIndex < NumRaysPerPixel; rayIndex++)
				{
					// -- Calculate ray origin and direction --
					// Jitter the starting point of the ray. This allows for a depth of field effect.
					float2 defocusJitter = RandomPointInCircle(rngState) * DefocusStrength / numPixels.x;
					float3 rayOrigin = _WorldSpaceCameraPos + camRight * defocusJitter.x + camUp * defocusJitter.y;

					// Jitter the focus point when calculating the ray direction to allow for blurring the image
					// (at low strengths, this can be used for anti-aliasing)
					float2 jitter = RandomPointInCircle(rngState) * DivergeStrength / numPixels.x;
					float3 jitteredFocusPoint = focusPoint + camRight * jitter.x + camUp * jitter.y;
					float3 rayDir = normalize(jitteredFocusPoint - rayOrigin);

					// Trace
					float sampleDist;
					totalIncomingLight += Trace(rayOrigin, rayDir, rngState, sampleDist);

					// Update distance sum/count
					if (sampleDist > NO_HIT) // Only count real geometry hits
					{
						distSum += sampleDist;
						distCount++;
					}
				}

				// Average the incoming light and distance
				float3 pixelCol = totalIncomingLight / NumRaysPerPixel;
				float distance = (distCount > 0) ? (distSum / distCount) : MAX_DISTANCE;

				return float4(pixelCol, distance);
			}

			ENDCG
		}
	}
}