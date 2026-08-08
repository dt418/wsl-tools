# Chính sách bảo mật

Dự án này hoạt động với quyền phá hủy đối với đăng ký WSL và các file VHDX. Các vấn đề bảo mật được xem trọng, kể cả các vấn đề có thể lừa người dùng mất dữ liệu.

## Phiên bản được hỗ trợ

Chỉ commit mới nhất trên nhánh mặc định được hỗ trợ. Hiện tại chưa có bản phát hành backport.

## Báo cáo lỗ hổng

Vui lòng báo cáo bằng cách mở GitHub issue trong kho lưu trữ này.

Khi báo cáo:

- Mô tả vấn đề và điều kiện cần để kích hoạt nó.
- **Không** đưa dữ liệu cá nhân, đường dẫn VHDX riêng tư hoặc định danh máy đầy đủ.
- Nếu bạn phát hiện điểm yếu trong mô hình an toàn (ví dụ đường dẫn có thể mất dữ liệu dù có các đảm bảo), hãy gắn rõ issue là lỗi mô hình an toàn.

Hiện chưa có kênh báo cáo riêng tư nào được cấu hình. Nếu thay đổi, chính sách này sẽ được cập nhật.

## Ghi chú thiết kế liên quan đến an toàn

- Thao tác phá hủy duy nhất là `wsl --unregister <distro>`.
- Unregister chỉ đạt được sau: hai bản xuất VHDX được xác minh độc lập, xác nhận vùng nguy hiểm, xác nhận gõ `RESTORE`, và xác minh lại giây cuối.
- Script không bao giờ ghi đè file hiện có; nó từ chối chạy khi đích đã tồn tại.
- Bản lưu trữ và VHDX live không bao giờ là cùng một file, và kiểm tra cùng đường dẫn sẽ chặn unregister nếu chúng trùng nhau một cách bất ngờ.
- Đường dẫn được so sánh không phân biệt hoa thường sau khi chuẩn hóa; biến môi trường được mở rộng trước khi so sánh.
- Launcher (`run-wsl-safe.cmd`) chạy kiểm tra cú pháp PowerShell và từ chối thực thi script khi xác thực cú pháp thất bại, giảm rủi ro chạy script bị hỏng.

## Tiết lộ có trách nhiệm

Vui lòng cho thời gian sửa lỗi và phát hành trước khi công khai thảo luận về lỗ hổng. Với riêng lỗi mô hình an toàn, chúng tôi đề nghị không công bố các bước tái hiện có thể gây mất dữ liệu cho người dùng khác trước khi bản sửa ra mắt.
