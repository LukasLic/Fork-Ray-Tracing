using UnityEngine;

[RequireComponent(typeof(Camera))]
public sealed class TopDownOrbitCamera : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float moveSpeed = 12f;
    [SerializeField] private float moveSmoothTime = 0.15f;

    [Header("Orbit")]
    [SerializeField] private float orbitYawSpeed = 220f;
    [SerializeField] private float groundPlaneY = 0f;

    [Header("Zoom")]
    [SerializeField] private float zoomSpeed = 30f;
    [SerializeField] private bool invertZoom = false;

    [SerializeField] private float minDistance = 4f;
    [SerializeField] private float maxDistance = 80f;

    [SerializeField] private float minOrthoSize = 2f;
    [SerializeField] private float maxOrthoSize = 40f;
    [SerializeField] private float orthoZoomSmoothTime = 0.12f;

    [Header("Time")]
    [SerializeField] private bool useUnscaledTime = false;

    private Camera _cam;

    private Vector3 _posVelocity;
    private Vector3 _targetPosition;

    private Quaternion _targetRotation;

    private bool _isOrbiting;
    private Vector3 _orbitPivot;

    private float _targetOrthoSize;
    private float _orthoSizeVelocity;

    private void Awake()
    {
        _cam = GetComponent<Camera>();

        _targetPosition = transform.position;
        _targetRotation = transform.rotation;

        if (_cam.orthographic)
            _targetOrthoSize = _cam.orthographicSize;
    }

    private void Update()
    {
        var dt = useUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;

        HandleMovement(dt);
        HandleOrbit(dt);
        HandleZoom(dt);
    }

    private void LateUpdate()
    {
        var dt = useUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;

        transform.position = Vector3.SmoothDamp(
            transform.position,
            _targetPosition,
            ref _posVelocity,
            moveSmoothTime,
            Mathf.Infinity,
            dt
        );

        transform.rotation = _targetRotation;

        if (_cam.orthographic)
        {
            _cam.orthographicSize = Mathf.SmoothDamp(
                _cam.orthographicSize,
                _targetOrthoSize,
                ref _orthoSizeVelocity,
                orthoZoomSmoothTime,
                Mathf.Infinity,
                dt
            );
        }
    }

    private void HandleMovement(float dt)
    {
        var input = new Vector2(
            Input.GetAxisRaw("Horizontal"),
            Input.GetAxisRaw("Vertical")
        );

        if (input.sqrMagnitude > 1f)
            input.Normalize();

        var forwardOnGround = Vector3.ProjectOnPlane(_targetRotation * Vector3.forward, Vector3.up).normalized;
        var rightOnGround = Vector3.ProjectOnPlane(_targetRotation * Vector3.right, Vector3.up).normalized;

        var move = (rightOnGround * input.x + forwardOnGround * input.y) * (moveSpeed * dt);
        _targetPosition += move;
    }

    private void HandleOrbit(float dt)
    {
        if (Input.GetMouseButtonDown(2))
            _isOrbiting = TryGetForwardGroundIntersection(_targetPosition, _targetRotation, out _orbitPivot);

        if (Input.GetMouseButtonUp(2))
            _isOrbiting = false;

        if (!_isOrbiting)
            return;

        var mouseX = Input.GetAxis("Mouse X");
        if (Mathf.Approximately(mouseX, 0f))
            return;

        var yawDelta = mouseX * orbitYawSpeed * dt;
        var yawRot = Quaternion.AngleAxis(yawDelta, Vector3.up);

        var offset = _targetPosition - _orbitPivot;
        offset = yawRot * offset;

        _targetPosition = _orbitPivot + offset;
        _targetRotation = yawRot * _targetRotation;
    }

    private void HandleZoom(float dt)
    {
        var scroll = Input.GetAxis("Mouse ScrollWheel");
        if (Mathf.Approximately(scroll, 0f))
            return;

        if (invertZoom)
            scroll = -scroll;

        if (_cam.orthographic)
        {
            _targetOrthoSize = Mathf.Clamp(
                _targetOrthoSize - (scroll * zoomSpeed),
                minOrthoSize,
                maxOrthoSize
            );
            return;
        }

        if (!TryGetForwardGroundIntersection(_targetPosition, _targetRotation, out var pivot))
            return;

        var offset = _targetPosition - pivot;
        var currentDistance = offset.magnitude;
        if (currentDistance < 0.0001f)
            return;

        var desiredDistance = Mathf.Clamp(
            currentDistance - (scroll * zoomSpeed),
            minDistance,
            maxDistance
        );

        _targetPosition = pivot + (offset / currentDistance) * desiredDistance;
    }

    private bool TryGetForwardGroundIntersection(Vector3 pos, Quaternion rot, out Vector3 hitPoint)
    {
        var plane = new Plane(Vector3.up, new Vector3(0f, groundPlaneY, 0f));
        var ray = new Ray(pos, rot * Vector3.forward);

        if (plane.Raycast(ray, out var enter) && enter > 0f)
        {
            hitPoint = ray.GetPoint(enter);
            return true;
        }

        var forwardOnGround = Vector3.ProjectOnPlane(ray.direction, Vector3.up);
        if (forwardOnGround.sqrMagnitude < 0.0001f)
        {
            hitPoint = pos;
            return false;
        }

        hitPoint = pos + forwardOnGround.normalized * 10f;
        hitPoint.y = groundPlaneY;
        return true;
    }
}
