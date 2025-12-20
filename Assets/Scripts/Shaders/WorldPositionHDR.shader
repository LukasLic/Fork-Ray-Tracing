Shader "Debug/WorldPositionHDR"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            ZWrite On
            ZTest LEqual
            Cull Back
            Blend Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldPos : TEXCOORD0;
            };

            v2f vert(appdata v)
            {
                v2f o;
                float4 wpos = mul(unity_ObjectToWorld, v.vertex);
                o.worldPos = wpos.xyz;
                o.pos = UnityObjectToClipPos(v.vertex);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                return float4(i.worldPos, 1.0);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
