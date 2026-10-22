# Hiển thị tiếng Việt trong terminal

KwVPS lưu mã nguồn bằng UTF-8 không BOM, xuống dòng LF. Chữ có dấu được in trực tiếp từ các tệp này. Nếu thấy chữ bị biến thành `?`, ký tự lạ hoặc ô vuông, hãy kiểm tra terminal đang dùng trước khi sửa tệp nguồn.

## Xem menu trên Windows

Mở PowerShell tại thư mục dự án và chạy:

```powershell
.\scripts\preview-utf8.ps1
```

Lệnh này chọn **Git Bash của Git for Windows**, đặt đầu vào/đầu ra UTF-8 và mở menu ở chế độ `--preview`. Có thể kiểm tra nhanh bằng `.\scripts\preview-utf8.ps1 -Mode help`. Chế độ preview chỉ hiển thị menu, không quản trị VPS.

Trên máy Windows hiện tại, lệnh `bash` mặc định trỏ tới `C:\Windows\System32\bash.exe` (bộ khởi chạy WSL), trong khi Git Bash có đường dẫn riêng. Vì vậy, gõ `bash kwvps --preview` trong PowerShell không bảo đảm chạy đúng Bash. Script phía trên tìm Git Bash qua lệnh `git.exe`.

Nếu PowerShell báo không cho chạy tệp `.ps1`, hãy mở Git Bash và chạy trực tiếp:

```bash
cd '/d/KwVPS Script'
bash kwvps --preview
```

Nếu chữ vẫn hiện ô vuông hoặc dấu bị tách, đổi font của terminal sang một font hỗ trợ tiếng Việt như Cascadia Mono hoặc Consolas. Trong Git Bash (mintty), mở **Options → Text** để chọn font. Chỉ đổi font ở máy tính; không cần cài font trên VPS.

## Khi kết nối VPS qua SSH

Chạy các lệnh chỉ đọc sau trong phiên SSH:

```bash
locale charmap
locale -a
printf '%s\n' 'Quản lý tiếng Việt'
```

`locale charmap` cần trả về `UTF-8`. Ubuntu 24.04 thường có locale `C.utf8` hoặc `C.UTF-8`. Nếu locale phiên hiện tại không phải UTF-8 nhưng `C.utf8` có trong danh sách, có thể thử riêng một lệnh:

```bash
LANG=C.UTF-8 LC_ALL=C.UTF-8 bash kwvps --help
```

Nếu dòng `printf` cũng lỗi, vấn đề nằm ở phiên terminal/SSH. Với PuTTY, chọn **Window → Translation → Remote character set: UTF-8** và font hỗ trợ tiếng Việt tại **Window → Appearance**. Với Windows Terminal, dùng font Cascadia Mono hoặc font Unicode tương đương. Sau khi đổi cài đặt, mở phiên SSH mới để thử lại.

Không cần đổi cấu hình SSH, cài font lên máy chủ hoặc chuyển mã các tệp KwVPS để khắc phục lỗi hiển thị ở terminal.
