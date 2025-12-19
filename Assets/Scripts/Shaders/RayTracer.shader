Shader "Custom/RayTracer"
{
	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			#pragma multi_compile _ DEBUG_VIS

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
			float SampleChance;

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

			// Alt. Mode Settings
			int rayPosOnly;
			sampler2D _Snapshot01;
			float4x4 _SnapViewProj;
			float4x4 _SnapCamLocalToWorld;
			float3 _SnapCamPos;

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
			};

			struct TriangleHitInfo
			{
				bool didHit;
				float dst;
				float3 hitPoint;
				float3 normal;
				int triIndex;
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
				float3 normal;
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

			// Crude sky colour function for background light
			float3 GetEnvironmentLight(float3 dir)
			{
				if (UseSky == 0) return 0;
				const float3 GroundColour = float3(0.35, 0.35, 0.35); // TODO: Make adjustable
				const float3 SkyColourHorizon = float3(1, 1, 1) * SunIntensity; // TODO: Temporary "sun"
				const float3 SkyColourZenith = float3(0.08, 0.37, 0.73) * sqrt(SunIntensity);
				
				// Combine ground, sky
				float skyGradientT = pow(smoothstep(0, 0.4, dir.y), 0.35);
				float groundToSkyT = smoothstep(-0.01, 0, dir.y);
				float3 skyGradient = lerp(SkyColourHorizon, SkyColourZenith, skyGradientT) * SunColour;
				float3 composite = lerp(GroundColour, skyGradient, groundToSkyT);

				// Add sun light
				float sun = pow(max(0, dot(dir, _WorldSpaceLightPos0.xyz)), SunFocus) * SunIntensity; // TODO
				// composite +=  sun * SunColour * (groundToSkyT >= 1); // TODO

				return composite;
			}

			// --- Ray Intersection Functions ---

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

			ModelHitInfo CalculateRayCollision(Ray worldRay, int bounce, out int2 stats)
			{
				stats = 0;
				ModelHitInfo result;
				result.didHit = false;
				// result.dst = 1.#INF;
				result.dst = MAX_DISTANCE;
				result.hitPoint = 0;
				result.normal = 0;
				Ray localRay;

				for (int i = 0; i < modelCount; i++)
				{
					Model model = ModelInfo[i];

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
						result.didHit = true;
						result.dst = hit.dst;
						result.normal = normalize(mul(model.localToWorldMatrix, float4(hit.normal, 0)));
						result.hitPoint = worldRay.origin + worldRay.dir * hit.dst;
						result.material = model.material;
					}

					// TODO: Apply the emission pass here.
				}

				return result;
			}

			float2 mod2(float2 x, float2 y)
			{
				return x - y * floor(x / y);
			}

			float3 CosineSampleHemisphere(float3 n, inout uint rngState)
			{
				float r1 = RandomValue(rngState);
				float r2 = RandomValue(rngState);

				float phi = 2 * PI * r1;
				float r = sqrt(r2);

				float x = r * cos(phi);
				float y = r * sin(phi);
				float z = sqrt(1 - r2);

				float3 t = normalize(abs(n.z) < 0.999 ? cross(n, float3(0,0,1)) : cross(n, float3(0,1,0)));
				float3 b = cross(t, n);

				return normalize(t * x + b * y + n * z);
			}

			float3 Trace(float3 rayOrigin, float3 rayDir, inout uint rngState, out float firstRayDst)
			{
				firstRayDst = NO_HIT;

				float3 incomingLight = 0;
				float3 rayColour = 1;
				
				int2 stats;
				float dstSum = 0;

				for (int bounceIndex = 0; bounceIndex < MaxBounceCount; bounceIndex++)
				{
					Ray ray;
					ray.origin = rayOrigin;
					ray.dir = rayDir;
					ModelHitInfo hitInfo = CalculateRayCollision(ray, bounceIndex, stats);

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
						rayOrigin = hitInfo.hitPoint + hitInfo.normal * 1e-4;

						// HERE
						// ---------------------------------------------------------------------------------
						// // Do a sun check
						// // float3 sunDir = normalize(_WorldSpaceLightPos0.xyz); // Directional sun direction
						// // float nDotL = max(0.0, dot(hitInfo.normal, sunDir));
						// // ---------------------------------------------------------------------------------
						// // Do a sun check
						// float3 sunAxis = normalize(_WorldSpaceLightPos0.xyz); // CHANGED: axis of the sun cone
						// // Derive a small cone from SunFocus (tweak if needed)
						// float cosThetaMax = pow(0.5, 1.0 / max(SunFocus, 1.0)); // CHANGED
						// float3 sunDir = SampleCone(sunAxis, cosThetaMax, rngState); // CHANGED: jittered sun direction
						// float nDotL = max(0.0, dot(hitInfo.normal, sunDir)); // CHANGED: use jittered dir

						// if (nDotL > 0.0)
						// {
						// 	Ray shadowRay;
						// 	shadowRay.origin = rayOrigin;
						// 	shadowRay.dir = sunDir;
						// 	shadowRay.invDir = 1.0 / shadowRay.dir;

						// 	int2 sunStats;
						// 	ModelHitInfo occ = CalculateRayCollision(shadowRay, bounceIndex + 1, sunStats);

						// 	if (!occ.didHit)
						// 	{
						// 		// Original / Option A: treat sun as directional/area light (stable energy)
						// 		// incomingLight += rayColour * (SunColour * SunIntensity) * nDotL; // CHANGED

						// 		// Option B: keep your "sun lobe" look (more variance, but matches your SunFocus idea)
						// 		float sun = pow(max(0.0, dot(sunDir, sunAxis)), SunFocus) * SunIntensity; // CHANGED
						// 		incomingLight += rayColour * (SunColour * sun) * nDotL; // CHANGED
						// 	}
						// }

						// float3 diffuseDir = CosineSampleHemisphere(hitInfo.normal, rngState);
						// ---------------------------------------------------------------------------------

						// ---------------------------------------------------------------------------------
						// float3 diffuseDir = normalize(hitInfo.normal + RandomDirection(rngState));
						float3 diffuseDir = CosineSampleHemisphereFast(hitInfo.normal, rngState); // TODO: This should be a bit quicker
						// ---------------------------------------------------------------------------------

						float3 specularDir = reflect(rayDir, hitInfo.normal);
						rayDir = normalize(lerp(diffuseDir, specularDir, material.smoothness * isSpecularBounce));

						// Update light calculations
						float3 emittedLight = material.emissionColour * material.emissionStrength;
						incomingLight += emittedLight * rayColour;
						rayColour *= lerp(material.colour, material.specularColour, isSpecularBounce);

						// Random early exit if ray colour is nearly 0 (can't contribute much to final result)
						float p = max(rayColour.r, max(rayColour.g, rayColour.b));
						if (RandomValue(rngState) >= p) {
							break;
						}
						rayColour *= 1.0f / p;
					}
					else
					{
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
				ModelHitInfo hitInfo = CalculateRayCollision(ray, 0, stats);

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
					if (!hitInfo.didHit) return 0;
					return hitInfo.normal * 0.5 + 0.5;
				}

				return float3(1, 0, 1); // Invalid test mode
			}

			// ###########################################################################
			// ###########################################################################
			// ###########################################################################

			bool HitWorldPos(float3 rayOrigin, float3 rayDir, out float3 worldPos)
			{
				int2 stats; // num triangle tests, num bounding box tests
				Ray ray;
				ray.origin = rayOrigin;
				ray.dir = rayDir;
				ModelHitInfo hitInfo = CalculateRayCollision(ray, 0, stats);

				// No hit, return black
				if(hitInfo.didHit == false)
				{
					// worldPos = float3(0.0, 0.0, 0.0);

					worldPos = _WorldSpaceCameraPos + rayDir * MAX_DISTANCE;
					return false;

					// float3 maxPos = _WorldSpaceCameraPos + rayDir * MAX_DISTANCE;
					// return float4(maxPos, 1.0);
				}

				worldPos = hitInfo.hitPoint;
				return true;
			}

			bool WorldToSnapshotUV(float3 worldPos, out float2 snapUV)
			{
				float4 clip = mul(_SnapViewProj, float4(worldPos, 1.0));

				// Behind snapshot camera
				if (clip.w <= 0.0)
				{
					snapUV = 0;
					return false;
				}

				float2 ndc = clip.xy / clip.w;          // -1..1
				snapUV = ndc * 0.5 + 0.5;               // 0..1

				// Outside snapshot image
				if (snapUV.x < 0.0 || snapUV.x > 1.0 || snapUV.y < 0.0 || snapUV.y > 1.0)
					return false;

				return true;
			}

			bool SnapshotMatchesPoint(float3 worldPos, float4 snap)
			{
				float _DepthEps = 0.15; // eg 0.05

				float snapDist = snap.a;

				// Snapshot had no hit there
				if (snapDist >= MAX_DISTANCE - 1e-3)
					return false;

				float expected = length(worldPos - _SnapCamPos);

				return abs(expected - snapDist) <= _DepthEps;
			}

			float3 SnapPrimaryRayDirWS(float2 snapUV)
			{
				float3 viewPlaneLocal = float3(snapUV - 0.5, 1.0) * ViewParams;
				float3 viewPlaneWorld = mul(_SnapCamLocalToWorld, float4(viewPlaneLocal, 1.0)).xyz;
				return normalize(viewPlaneWorld - _SnapCamPos);
			}

			// Returns false if the snapshot had no hit at that UV
			bool SnapUVToWorldPos(float2 snapUV, out float3 worldPos, out float4 snapSample)
			{
				snapSample = tex2D(_Snapshot01, snapUV);
				float dist = snapSample.a;

				if (dist >= MAX_DISTANCE - 1e-3)
				{
					worldPos = 0;
					return false;
				}

				float3 dirWS = SnapPrimaryRayDirWS(snapUV);
				worldPos = _SnapCamPos + dirWS * dist;
				return true;
			}

			float3 RunFinalCompose(float3 camPos, float3 focusPoint, v2f i)
			{
				return tex2D(_Snapshot01, i.uv).rgb;

				float3 rayDir = normalize(focusPoint - camPos);
				float3 worldPos;
				bool isHit = HitWorldPos(camPos, rayDir, worldPos);

				// // [unroll(999)]
				// for (int i = 0; i < 20; i++)
				// {
				// 	for (int j = 0; j < 20; j++)
				// 	{
				// 		float2 uv = float2(i, j) / float2(1000, 1000);
				// 		float4 s = tex2D(_Snapshot01, uv);

				// 		float3 snapWorldPos;
				// 		float4 snap;
				// 		if (SnapUVToWorldPos(uv, snapWorldPos, snap))
				// 		{
				// 			// snapWorldPos is the reconstructed hit position in world space
				// 			// snap.rgb is the snapshot color at that hit
				// 			if (length(snapWorldPos - worldPos) < 1)
				// 			{
				// 				return snap.rgb;
				// 			}
				// 		}
				// 	}
				// }

				// float2 snapUV;
				// if(WorldToSnapshotUV(worldPos, snapUV))
				// {
				// 	// snap.rgb = color
				// 	// snap.a = distance (from snapshot camera)
				// 	float4 snap = tex2D(_Snapshot01, snapUV);

				// 	if(SnapshotMatchesPoint(worldPos, snap))
				// 	{
				// 		// If the snapshot matches the world position, use it
				// 		return snap.rgb;
				// 	}
				// }

				return float3(1.0, 0.0, 0.0);
			}

			// ###########################################################################
			// ###########################################################################
			// ###########################################################################


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

				// ############################################################################
				// ############################################################################

				if(rayPosOnly == 1)
				{
					return float4(RunFinalCompose(_WorldSpaceCameraPos, focusPoint, i), 1.0);
				}
				
				// ############################################################################
				// ############################################################################

				// Trace multiple rays and average together
				float3 totalIncomingLight = 0;
				// Distance averaging
				float distSum = 0.0;
				int distCount = 0;

				if(RandomValue(rngState) > SampleChance)
				{
					return float4(0,0,0, 0);
				}

				for (int rayIndex = 0; rayIndex < NumRaysPerPixel; rayIndex++)
				{
					// -- Calculate ray origin and direction --
					// Jitter the starting point of the ray. This allows for a depth of field effect.
					float2 defocusJitter = RandomPointInCircle(rngState) * DefocusStrength / numPixels.x;
					// Disable jitter on the first ray to improve distance sampling accuracy.
					defocusJitter = rayIndex == 0 ? 0 : defocusJitter;

					float3 rayOrigin = _WorldSpaceCameraPos + camRight * defocusJitter.x + camUp * defocusJitter.y;

					// Jitter the focus point when calculating the ray direction to allow for blurring the image
					// (at low strengths, this can be used for anti-aliasing)
					float2 jitter = RandomPointInCircle(rngState) * DivergeStrength / numPixels.x;
					// Disable jitter on the first ray to improve distance sampling accuracy.
					jitter = rayIndex == 0 ? 0 : jitter;

					float3 jitteredFocusPoint = focusPoint + camRight * jitter.x + camUp * jitter.y;
					float3 rayDir = normalize(jitteredFocusPoint - rayOrigin);

					// Trace
					float sampleDist;
					totalIncomingLight += Trace(rayOrigin, rayDir, rngState, sampleDist);

					// Update distance sum/count
					if (rayIndex == 0 && sampleDist > NO_HIT) // Only count real geometry hits
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