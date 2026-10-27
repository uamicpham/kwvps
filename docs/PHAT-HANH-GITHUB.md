# Phát hành KwVPS qua GitHub

## Trạng thái

Ghi chú phát hành [0.50.19](RELEASE-NOTES-0.50.19.md) mô tả bản hiện tại tại `uamicpham/kwvps`. Chỉ coi một tag là bản công khai sau khi workflow tạo GitHub Release và tài sản tải về thành công. README có lệnh cài ngắn tự lấy release mới nhất và lệnh ghim tag/checksum để kiểm soát chặt hơn. VPS đã cài có thể chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS**; gói được xác minh bằng SHA-256 từ GitHub API trước khi áp dụng. Bản cài mới chỉ hỗ trợ VPS Ubuntu Server 24.04 sạch, x86_64 và systemd; không cài đè LarVPS hay web stack khác.

## Chuẩn bị GitHub

1. Repository **public** của dự án là `https://github.com/uamicpham/kwvps`. Repo public không cần token để VPS tải bản phát hành. Không gửi token/password/private key vào chat.
2. Để đẩy mã, đăng nhập GitHub trên máy phát triển bằng Git Credential Manager hoặc `gh auth login` trong thiết bị của bạn. Nếu GitHub yêu cầu PAT, tạo fine-grained token chỉ cho repository này với `Contents: Read and write`; nhập vào công cụ xác thực trên máy, **không lưu token trong dự án**. Bật 2FA cho tài khoản.
3. Rà `git status` và nội dung commit trước khi push. Không đưa `.env`, backup, database dump, Cloudflare token, Tunnel token hay khóa SSH vào GitHub. CI phải đạt trước khi gắn tag.

## Đóng gói

Sau khi kiểm thử và đổi `KW_VERSION` thành `x.y.z` ổn định, có thể kiểm tra gói cục bộ trên Linux:

```bash
bash scripts/package-release.sh owner/repo
```

Script đóng gói theo danh sách file cho phép vào `dist/kwvps-x.y.z.tar.gz`, kèm `dist/kwvps-x.y.z.tar.gz.sha256`. Nó từ chối ghi đè gói đã có. Khi đẩy tag `vx.y.z`, workflow `.github/workflows/release.yml` kiểm tra version, chạy test và ShellCheck, đóng gói rồi tự tạo GitHub Release với hai asset trên và `docs/RELEASE-NOTES-x.y.z.md`. Không cần tải asset thủ công nếu workflow thành công. Kiểm tra lại release, tài sản tải về và SHA-256 trên GitHub trước khi đưa lệnh cài cho người dùng.

## Lệnh cài một dòng

Lệnh cài ngắn và lệnh ghim phiên bản có xác minh SHA-256 bootstrap nằm trong [README](../README.md#cài-bằng-một-dòng-trên-vps-mới). Lệnh ngắn tải bootstrap từ nhánh `main` và chọn release mới nhất; nó không cần sửa khi phát hành phiên bản mới, nhưng không xác minh checksum của chính bootstrap và nhánh `main` có thể thay đổi. Bootstrap xác minh SHA-256 của gói release trước khi cài. Lệnh dài kiểm tra checksum bootstrap trước khi chạy và ghim release `v0.50.1`. VPS cần `curl`, `python3`, `tar`, `sha256sum`, `sudo` hoặc quyền root và Ubuntu 24.04 sạch. Bộ cài tự kiểm tra xung đột, bản vá PHP 8.3, hỏi `INSTALL KWVPS` và không tự bật UFW/SSL.

Sau khi cài, chạy `kwvps --doctor` và `kwvps`. Gói release mang `release-repo` để bộ cài lưu nguồn GitHub công khai trong `/etc/kwvps/github-repo`; menu Update dùng GitHub Release API, chỉ chấp nhận bản mới hơn có SHA-256 hợp lệ do API trả về. Nếu repo private, thiết kế tải không dùng token hiện tại sẽ không hoạt động; cần thảo luận cơ chế phát hành riêng, không dán token vào lệnh cài.

`scripts/bootstrap-release.sh` tải release public, xác minh SHA-256 và kiểm tra archive trước khi chạy installer. Lệnh ngắn theo nhánh `main` nhưng không kiểm tra checksum bootstrap; lệnh dài ghim tag và kiểm tra checksum. Release workflow chỉ xuất bản nếu syntax, smoke, ShellCheck, Bats, Python và kiểm tra checksum gói đều đạt.

## Điều kiện phát hành

- CI trên Ubuntu 24.04: Bash syntax, ShellCheck, Bats, smoke tests.
- Kiểm thử cài mới, mở menu, cập nhật, và rollback trên VPS trắng có snapshot/console cứu hộ.
- Rà các chức năng ghi/xóa/remote API theo nguyên tắc quyền tối thiểu, đầu vào hợp lệ, xác nhận rõ, không in bí mật. Bài test hiện có không chứng minh toàn bộ menu an toàn cho sản xuất.
- Không tự nhận hỗ trợ mọi Linux; Ubuntu/Debian phiên bản khác phải được kiểm thử riêng.
