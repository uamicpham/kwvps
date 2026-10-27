# KwVPS 0.50.20-dev — chuyển connector Tunnel khi đổi tên site

- Khi đổi tên site HTTP do KwVPS quản lý, connector Tunnel riêng được chuyển sang site ID mới. Token giữ nguyên, service mới giữ trạng thái enabled/active của service cũ.
- KwVPS kiểm tra unit và quyền token trước khi đổi, dừng connector cũ trước khi khởi động connector mới, và thử phục hồi service/token cũ nếu giao dịch đổi tên thất bại. Bản sao token cũ nằm trong vùng backup root-only của lần đổi tên.
- Hostname route/DNS trên Cloudflare vẫn do người quản trị cập nhật; KwVPS không gọi Cloudflare API để sửa route. Site có vhost SSL, FastCGI cache hoặc cấu hình Nginx tùy biến vẫn bị từ chối bởi chức năng đổi tên.
- Đây là bản thử nghiệm trên `main`, chưa phải GitHub Release. Trước khi phát hành, đổi phiên bản từ `0.50.20-dev` sang `0.50.20` và chạy đầy đủ CI.
