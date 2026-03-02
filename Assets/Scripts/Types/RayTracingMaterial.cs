using UnityEngine;

[System.Serializable]
public struct RayTracingMaterial
{
	public enum MaterialFlag
	{
        None = 0,
        CheckerPattern = 1,
        InvisibleLight = 2,
        Invisible = 3,
    }

	public Color colour;
	public Color emissionColour;
	public Color specularColour;
	public float emissionStrength;
	[Range(0, 1)] public float smoothness;
	[Range(0, 1)] public float specularProbability;
	public MaterialFlag flag;
	public int shadowObject;

	public int normalScale;
    public int normalMapIndex;
    public Vector4 uvST;         // (scaleX, scaleY, offsetX, offsetY)

 //   public void SetDefaultValues()
	//{
	//	colour = Color.white;
	//	emissionColour = Color.white;
	//	emissionStrength = 0;
	//	specularColour = Color.white;
	//	smoothness = 0;
	//	specularProbability = 1;
	//	normalScale = 1;
 //       normalMapIndex = -1;
 //       uvST = new Vector4(1, 1, 0, 0);
	//	shadowObject = 0;
 //   }

	public static RayTracingMaterial DuplicateFrom(RayTracingMaterial other, MaterialFlag? newFlag = null)
	{
        return new RayTracingMaterial()
		{
			colour = other.colour,
			emissionColour = other.emissionColour,
			emissionStrength = other.emissionStrength,
			specularColour = other.specularColour,
			smoothness = other.smoothness,
			specularProbability = other.specularProbability,
			flag = newFlag ?? other.flag,
			normalScale = other.normalScale,
			normalMapIndex = other.normalMapIndex,
			uvST = other.uvST,
			shadowObject = other.shadowObject,
        };
    }
}