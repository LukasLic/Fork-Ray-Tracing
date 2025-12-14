using UnityEngine;

[AddComponentMenu("Camera/Free Fly Camera")]
public class FreeFlyCamera : MonoBehaviour
{
    [Header("Look")]
    public float lookSensitivity = 2f;
    public bool holdRightMouseToLook = true;
    public bool lockCursorOnStart = true;

    [Header("Move")]
    public float moveSpeed = 10f;
    public float sprintMultiplier = 3f;
    public float scrollSpeedStep = 2f;

    [Header("Keys")]
    public KeyCode upKey = KeyCode.E;
    public KeyCode downKey = KeyCode.Q;
    public KeyCode sprintKey = KeyCode.LeftShift;

    float _yaw;
    float _pitch;
    bool _cursorLocked;

    void Start()
    {
        var euler = transform.rotation.eulerAngles;
        _yaw = euler.y;
        _pitch = euler.x;

        if (lockCursorOnStart && (!holdRightMouseToLook))
        {
            SetCursorLocked(true);
        }
    }

    void Update()
    {
        HandleCursorLock();
        HandleLook();
        HandleMove();
        HandleSpeedAdjust();
    }

    void HandleCursorLock()
    {
        if (!holdRightMouseToLook)
        {
            if (!_cursorLocked && lockCursorOnStart)
                SetCursorLocked(true);

            if (Input.GetKeyDown(KeyCode.Escape))
                SetCursorLocked(false);

            return;
        }

        if (Input.GetMouseButtonDown(1))
            SetCursorLocked(true);

        if (Input.GetKeyDown(KeyCode.Escape))
            SetCursorLocked(false);
    }

    void HandleLook()
    {
        var canLook = holdRightMouseToLook ? (_cursorLocked && Input.GetMouseButton(1)) : _cursorLocked;
        if (!canLook) return;

        var mouseX = Input.GetAxisRaw("Mouse X") * lookSensitivity;
        var mouseY = Input.GetAxisRaw("Mouse Y") * lookSensitivity;

        _yaw += mouseX;
        _pitch -= mouseY;
        _pitch = Mathf.Clamp(_pitch, -89f, 89f);

        transform.rotation = Quaternion.Euler(_pitch, _yaw, 0f);
    }

    void HandleMove()
    {
        var h = Input.GetAxisRaw("Horizontal");
        var v = Input.GetAxisRaw("Vertical");

        var up = 0f;
        if (Input.GetKey(upKey)) up += 1f;
        if (Input.GetKey(downKey)) up -= 1f;

        var localDir = new Vector3(h, up, v);
        if (localDir.sqrMagnitude > 1f) localDir.Normalize();

        var speed = moveSpeed;
        if (Input.GetKey(sprintKey)) speed *= sprintMultiplier;

        var worldDir = (transform.right * localDir.x) + (transform.up * localDir.y) + (transform.forward * localDir.z);
        transform.position += worldDir * speed * Time.deltaTime;
    }

    void HandleSpeedAdjust()
    {
        var scroll = Input.mouseScrollDelta.y;
        if (Mathf.Abs(scroll) <= 0f) return;

        moveSpeed = Mathf.Max(0.1f, moveSpeed + (scroll * scrollSpeedStep));
    }

    void SetCursorLocked(bool locked)
    {
        _cursorLocked = locked;
        Cursor.lockState = locked ? CursorLockMode.Locked : CursorLockMode.None;
        Cursor.visible = !locked;
    }
}
