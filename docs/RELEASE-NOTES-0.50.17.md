# KwVPS 0.50.17 — tải Node.js trong sandbox APT

- Khi tải gói Node.js 24 riêng cho Laravel, KwVPS tạo thư mục tạm chỉ cho user `_apt` ghi. APT có thể tải với quyền hạn chế thay vì cảnh báo phải tải bằng root.
- Sau khi tải, KwVPS thu hồi quyền ghi của `_apt`, kiểm tra đúng một gói `.deb`, xác minh SHA-256 từ chỉ mục APT đã ký rồi mới giải nén.
- CI kiểm tra quyền thư mục và thử `apt-get download` trên Ubuntu 24.04, xác nhận không có cảnh báo `unsandboxed`.

Node.js đã cài thành công từ bản trước không cần cài lại. VPS đã cài có thể nâng cấp mã bằng **Quản lý Update → Kiểm tra / cập nhật KwVPS**.
