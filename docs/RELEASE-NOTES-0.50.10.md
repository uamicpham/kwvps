# KwVPS 0.50.10 — cải thiện quy trình Laravel theo site

- **Sửa .env**: nếu `deploy/shared/.env` hiện có nhưng thuộc `root` hoặc user site với quyền chưa đúng, KwVPS hiển thị metadata và hỏi `y/N` trước khi đổi thành user site, quyền `0600`. Giữ nguyên nội dung; từ chối symlink, hardlink hoặc file thuộc user khác. Deploy dùng cùng điều kiện an toàn nhưng không tự sửa file.
- **Clone Git qua SSH**: mục Clone tạo Deploy Key Ed25519 riêng cho site khi chưa có và hiển thị public key để thêm vào repository. Chọn lại mục này sẽ hiển thị cùng key, không ghi đè private key sau lần clone thất bại. Người dùng vẫn cần xác minh host key GitHub và thêm Deploy Key quyền đọc trong GitHub.
- **Công cụ Laravel**: mục trạng thái liệt kê công cụ thiếu và cho chọn cài từng mục, gồm Git, Composer, PHP CLI đúng phiên bản site và công cụ frontend tùy dự án. APT được mô phỏng trước khi xác nhận; các nguồn PHP/Node được kiểm tra. Cài đặt có thể thay đổi package trên toàn VPS, không chỉ site được chọn.
- Bổ sung kiểm thử cho menu công cụ, Deploy Key và quyền `.env`.

Release này **không tự cập nhật VPS**. Trên VPS có website thật, sao lưu/snapshot rồi dùng menu **Quản lý Update → Kiểm tra / cập nhật KwVPS** khi sẵn sàng thử. Chưa xác nhận deploy Laravel đầu-cuối trên VPS production; backup source hiện chỉ gồm `public/`, chưa gồm `.env`, release, storage hay DB Laravel.
