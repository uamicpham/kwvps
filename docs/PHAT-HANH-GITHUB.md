# Phát hành KwVPS qua GitHub

## Trạng thái

KwVPS 0.50.0 đã phát hành tại [uamicpham/kwvps](https://github.com/uamicpham/kwvps). Bản 0.50.1 chốt lệnh cài một dòng ghim tag và SHA-256 bootstrap. Bản cài mới chỉ hỗ trợ VPS Ubuntu Server 24.04 sạch, x86_64 và systemd; không cài đè LarVPS hay web stack khác.

## Chuẩn bị GitHub

1. Repository **public** của dự án là `https://github.com/uamicpham/kwvps`. Repo public không cần token để VPS tải bản phát hành. Không gửi token/password/private key vào chat.
2. Để đẩy mã, đăng nhập GitHub trên máy phát triển bằng Git Credential Manager hoặc `gh auth login` trong thiết bị của bạn. Nếu GitHub yêu cầu PAT, tạo fine-grained token chỉ cho repository này với `Contents: Read and write`; nhập vào công cụ xác thực trên máy, **không lưu token trong dự án**. Bật 2FA cho tài khoản.
3. Rà `git status` và nội dung commit trước khi push. Không đưa `.env`, backup, database dump, Cloudflare token, Tunnel token hay khóa SSH vào GitHub. CI phải đạt trước khi gắn tag.

## Đóng gói

Sau khi kiểm thử và đổi `KW_VERSION` thành `x.y.z` ổn định, chạy trên Linux:

```bash
bash scripts/package-release.sh owner/repo
```

Script đóng gói theo danh sách file cho phép vào `dist/kwvps-x.y.z.tar.gz`, kèm `dist/kwvps-x.y.z.tar.gz.sha256`. Nó từ chối ghi đè gói đã có. Tạo GitHub Release với tag `vx.y.z` và tải chính xác archive này lên. Kiểm tra SHA-256 của asset trên GitHub khớp file local.

## Lệnh cài một dòng

Lệnh cài chính thức và SHA-256 bootstrap đã xác minh nằm trong [README](../README.md#cài-bằng-một-dòng-trên-vps-mới). Lệnh tải bootstrap từ tag cố định qua HTTPS, kiểm tra SHA-256 **trước** khi chạy; bootstrap tiếp tục kiểm tra gói release và yêu cầu nhập `INSTALL KWVPS`. Không dùng `curl ... | bash` từ nhánh `main` đổi liên tục. VPS cần `curl`, `python3`, `tar`, `sha256sum`, `sudo` hoặc quyền root và Ubuntu 24.04 sạch. Bộ cài tự kiểm tra xung đột, bản vá PHP 8.3 và không tự bật UFW/SSL.

Sau khi cài, chạy `kwvps --doctor` và `kwvps`. Gói release mang `release-repo` để bộ cài lưu nguồn GitHub công khai trong `/etc/kwvps/github-repo`; menu Update dùng GitHub Release API, chỉ chấp nhận bản mới hơn có SHA-256 hợp lệ do API trả về. Nếu repo private, thiết kế tải không dùng token hiện tại sẽ không hoạt động; cần thảo luận cơ chế phát hành riêng, không dán token vào lệnh cài.

`scripts/bootstrap-release.sh` tải release public, xác minh SHA-256 và kiểm tra archive trước khi chạy installer. **Không** hướng dẫn người dùng `curl | bash` trực tiếp từ nhánh `main`: bản thân bootstrap được ghim bằng tag và checksum trong lệnh một dòng công bố. Release workflow chỉ xuất bản nếu syntax, smoke, ShellCheck, Bats, Python và kiểm tra checksum gói đều đạt.

## Điều kiện phát hành

- CI trên Ubuntu 24.04: Bash syntax, ShellCheck, Bats, smoke tests.
- Kiểm thử cài mới, mở menu, cập nhật, và rollback trên VPS trắng có snapshot/console cứu hộ.
- Rà các chức năng ghi/xóa/remote API theo nguyên tắc quyền tối thiểu, đầu vào hợp lệ, xác nhận rõ, không in bí mật. Bài test hiện có không chứng minh toàn bộ menu an toàn cho sản xuất.
- Không tự nhận hỗ trợ mọi Linux; Ubuntu/Debian phiên bản khác phải được kiểm thử riêng.
