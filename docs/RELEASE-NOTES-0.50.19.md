# KwVPS 0.50.19 — dùng đúng Deploy Key khi Pull code

- Laravel Clone/Pull qua SSH luôn chỉ định khóa `id_ed25519` của user site với `IdentitiesOnly=yes`, thay vì để SSH tự chọn khóa từ môi trường VPS.
- Trước kết nối, KwVPS kiểm tra owner/quyền của thư mục `.ssh` và private key. Khóa không được in ra màn hình hay gửi trong lệnh Git.
- Nếu GitHub vẫn từ chối, menu Pull hiện user site và URL repository cần kiểm tra. Vào lại **Clone Git vào source** sẽ hiện cùng public key để đối chiếu với GitHub → repository → Settings → Deploy keys; thao tác này không thay private key hiện có.
- Lệnh Pull chỉ cập nhật `source/`; website chỉ đổi khi chạy Deploy release.
- Đổi tên miền nay nhận diện vhost Laravel release HTTP do KwVPS tạo, gồm cả cấu hình Real IP cho Tunnel. Sau khi đổi, document root tiếp tục trỏ tới `deploy/current/public`; KwVPS kiểm tra release hiện tại và health check. Vhost SSL, cache hoặc cấu hình chỉnh tay vẫn cần xử lý riêng.

VPS đã cài có thể cập nhật tại **Quản lý Update → Kiểm tra / cập nhật KwVPS**, sau đó thoát và mở lại `sudo kwvps`.
