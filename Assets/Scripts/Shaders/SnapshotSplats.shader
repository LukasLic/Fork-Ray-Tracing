Shader "Hidden/SnapshotSplats"
{
    SubShader
    {
        Tags { "Queue"="Transparent" }
        Pass
        {
            ZTest LEqual
            ZWrite Off
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha

            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"

            sampler2D _SnapshotTex;
            float4 _SnapshotTex_TexelSize; // x=1/w y=1/h z=w w=h

            float3 _SnapshotCamPos;
            float3 _SnapshotViewParams;
            float4x4 _SnapshotCamLocalToWorld;

            float _MaxDistance;
            float _SplatSizeWorld;

            struct appdata
            {
                float3 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 col : TEXCOORD0;
                float  valid : TEXCOORD1;
            };

            float3 PrimaryRayDirWS(float2 uv)
            {
                float3 viewPlaneLocal = float3(uv - 0.5, 1.0) * _SnapshotViewParams;
                float3 viewPlaneWorld = mul(_SnapshotCamLocalToWorld, float4(viewPlaneLocal, 1.0)).xyz;
                return normalize(viewPlaneWorld - _SnapshotCamPos);
            }

            v2f vert(appdata v, uint iid : SV_InstanceID)
            {
                v2f o;

                uint w = (uint)_SnapshotTex_TexelSize.z;
                uint h = (uint)_SnapshotTex_TexelSize.w;

                uint x = iid % w;
                uint y = iid / w;
                float2 suv = (float2(x, y) + 0.5) / float2(w, h);

                float4 s = tex2Dlod(_SnapshotTex, float4(suv, 0, 0));
                float dist = s.a;

                o.valid = dist < _MaxDistance - 1e-3;
                o.col = float4(s.rgb, 1.0);

                if (!o.valid)
                {
                    o.pos = float4(0,0,0,0);
                    return o;
                }

                float3 dirWS = PrimaryRayDirWS(suv);
                float3 worldPos = _SnapshotCamPos + dirWS * dist;

                float3 camRight = unity_CameraToWorld._m00_m10_m20;
                float3 camUp    = unity_CameraToWorld._m01_m11_m21;

                float2 off = v.vertex.xy * _SplatSizeWorld;
                float3 splatPosWS = worldPos + camRight * off.x + camUp * off.y;

                o.pos = mul(UNITY_MATRIX_VP, float4(splatPosWS, 1.0));
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                if (i.valid < 0.5) discard;
                return i.col;
            }
            ENDCG
        }
    }
}
