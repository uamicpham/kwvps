# KwVPS 0.50.16 — sửa phát hiện Node.js 24 từ NodeSource

- Khi cài Node.js riêng cho build Laravel, KwVPS đọc toàn bộ kết quả `apt-cache policy` trước khi chọn phiên bản. Trước đây việc dừng đọc sớm có thể khiến `apt-cache` bị SIGPIPE khi NodeSource liệt kê nhiều phiên bản, rồi menu báo nhầm không tìm được Node.js 24.
- Thêm kiểm thử với danh sách APT dài và `pipefail` để ngăn lỗi tái diễn.

Trên VPS đã cài, chọn **Quản lý Update → Kiểm tra / cập nhật KwVPS** rồi mở lại `sudo kwvps`. Sau đó vào **Laravel theo site → Kiểm tra trạng thái/công cụ** và cài Node.js/npm lại. Node.js được giải nén riêng cho KwVPS; thao tác này không thay Node/npm toàn VPS.
