Shader "Hidden/WorldPosReplacementHDR"
{
    // Opaque / most materials
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            ZWrite On
            ZTest LEqual
            Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata { float4 vertex : POSITION; };
            struct v2f { float4 pos : SV_POSITION; float3 wpos : TEXCOORD0; };

            v2f vert(appdata v)
            {
                v2f o;
                float4 w = mul(unity_ObjectToWorld, v.vertex);
                o.wpos = w.xyz;
                o.pos = UnityObjectToClipPos(v.vertex);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                return float4(i.wpos, 1.0);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
