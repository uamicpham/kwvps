# KwVPS 0.50.14 — Laravel deploy và chế độ kết nối từng site

- Site mới được ghi nhận ở chế độ DNS thông thường. Khi cấu hình Cloudflare Tunnel, menu hỏi chọn site đã có route để bật chế độ Tunnel và Real IP riêng cho site đó. Một `cloudflared.service` vẫn dùng chung một Tunnel token trên VPS; chưa quản lý nhiều connector cho nhiều tài khoản Cloudflare.
- Laravel Deploy tự pull nhánh Git hiện tại trước khi tạo release. Mục Pull code riêng vẫn có để cập nhật `source/` mà chưa chuyển website.
- Menu Deploy hỏi riêng có chạy migration không, mặc định Không. Lệnh `sudo kwvps --laravel-deploy DOMAIN --migrate` cho phép chọn chạy `artisan migrate --force` trong release mới trước khi đổi `current`; lệnh vẫn hỏi xác nhận. Backup database trước khi dùng: rollback code không hoàn tác migration, và website cũ vẫn phục vụ trong lúc migration chạy.
- KwVPS không tự chạy các bước đặc thù của ứng dụng như xuất bản Filament/Livewire assets, cache riêng, queue restart hoặc kiểm tra endpoint riêng. Đối chiếu quy trình của từng ứng dụng trước khi bỏ script deploy riêng.

Workflow phát hành chạy Bash syntax, smoke, ShellCheck, Bats và kiểm tra checksum trên Ubuntu 24.04. Phần migration chưa được kiểm thử đầu-cuối trên VPS có website thật.
