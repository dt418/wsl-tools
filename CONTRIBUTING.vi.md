# Đóng góp cho WSL Safe Backup / Move / Restore

Cảm ơn bạn đã quan tâm đến việc đóng góp! Đây là một công cụ nhỏ nhưng mang tính an toàn cao: một lỗi ở đây có thể phá hủy distro WSL của người dùng. Ngưỡng chấp nhận cho các thay đổi đụng đến bước phá hủy được đặt cao có chủ đích, và mọi người review sẽ hỏi *"chuyện gì xảy ra nếu bước kiểm tra này bị bỏ qua hoặc thất bại?"*

## Phạm vi dự án

- Luồng sao lưu, di chuyển và khôi phục cho distro WSL2 (bản cài từ Microsoft Store).
- Launcher (`run-wsl-safe.cmd`) và bước kiểm tra cú pháp của nó.
- Tài liệu giải thích mô hình an toàn.

## Bắt đầu

Không cần bước build. Dự án chạy trên Windows PowerShell 5.1+ tiêu chuẩn.

Để xác thực thay đổi của bạn, chạy đúng lệnh kiểm tra cú pháp mà launcher dùng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorList=$null; $TokenList=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\wsl-safe-backup-restore.ps1'),[ref]$TokenList,[ref]$ErrorList) > $null; if($ErrorList.Count -gt 0){ $ErrorList | ForEach-Object { Write-Host ('Line {0}, Col {1}: {2}' -f $_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message) }; exit 1 } else { Write-Host '[OK] Syntax valid.'; exit 0 }"
```

## Kiểm tra

Trước khi gửi thay đổi, hãy chạy toàn bộ bộ kiểm tra:

```powershell
npm install
npm run validate
```

Lệnh này chạy hai bước kiểm tra:

- **Kiểm tra tài liệu** (`npm run validate:docs`) — phân tích mọi sơ đồ `mermaid` (qua `scripts/validate-docs.mjs`), xác minh mọi code fence trong Markdown cân bằng, và kiểm tra mọi link nội bộ trong Markdown trỏ đến file thật.
- **Kiểm tra cú pháp PowerShell** (`npm run validate:ps1`) — cùng bước kiểm tra parser mà launcher thực hiện, không thực thi script (`scripts/validate-ps1.mjs` + `scripts/validate-ps1.ps1`). Trên hệ thống không phải Windows, bước này tự động bỏ qua.

## Kiểm thử

> **Cảnh báo:** luồng MOVE tắt WSL và gọi `wsl --unregister`. Chỉ kiểm thử luồng đầy đủ trên một distro dùng một lần hoặc máy mà bạn chấp nhận mất, và luôn giữ bản sao lưu riêng của mình.

- **BACKUP ONLY** — an toàn để kiểm thử trên máy thật.
- **SAFE MOVE / RESTORE** — kiểm thử trong máy ảo hoặc với distro dùng một lần trước khi tin cậy nó.

Nếu bạn thay đổi hành vi, hãy mô tả chính xác bạn đã kiểm thử gì trong phần mô tả pull request.

## Nguyên tắc

- Tuân theo phong cách hiện có: banner chú thích, helper `Stop-Script` / `Exit-Safely`, đầu ra `Write-Host` theo từng phần, và xuất dựa trên `wsl --export ... --vhd`.
- **Không bao giờ làm yếu cổng chặn an toàn.** Một thay đổi gỡ bỏ, bỏ qua, đảo thứ tự hoặc vòng qua bước xác minh sẽ bị chất vấn khi review, và thường bị từ chối nếu không có lý do mạnh.
- Giữ các thao tác phá hủy sau cùng một chuỗi xác nhận (xác nhận menu, xác nhận vùng nguy hiểm, gõ `RESTORE`, kiểm tra giây cuối).
- Không đưa vào việc ghi đè âm thầm các file hiện có.
- Ưu tiên pull request nhỏ, mang tính bổ sung; cập nhật README/CHANGELOG khi hành vi thay đổi.
- Dùng động từ PowerShell đã chuẩn hóa và giữ hàm tập trung; nên tái sử dụng các helper hiện có thay vì viết trùng.

## Thông điệp commit

Dùng tóm tắt ngắn, mệnh lệnh (ví dụ `Fix live VHDX size check`, `Document failure recovery matrix`). Nếu thay đổi đụng đến mô hình an toàn, hãy nói rõ trong phần thân.

## Pull request

1. Giải thích *tại sao* cần thay đổi và liên kết issue liên quan nếu có.
2. Mô tả kiểm thử bạn đã thực hiện.
3. Cập nhật CHANGELOG và tài liệu nếu hành vi hiển thị với người dùng thay đổi.
4. Giữ diff tập trung — thay đổi định dạng không liên quan khiến review khó hơn.

## Câu hỏi

Mở issue nếu bạn không chắc thay đổi có phù hợp với dự án trước khi đầu tư thời gian vào một PR lớn.
