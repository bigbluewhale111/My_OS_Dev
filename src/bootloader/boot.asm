org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

;
;   FAT12
;

jmp short start
nop

bpb_OEM                             db "MSWIN4.1"
bpb_bytes_per_sector                dw 512
bpb_sectors_per_cluster             db 1
bpb_reserved_sectors_count          dw 1
bpb_FATs_count                      db 2
bpb_root_directory_entry_count      dw 0E0h
bpb_total_sectors                   dw 2880
bpb_media_indicator                 db 0F0h
bpb_sectors_per_FAT_count           dw 9
bpb_sectors_per_track_count         dw 18
bpb_heads_count                     dw 2
bpb_hidden_sectors_count            dd 0
bpb_large_sectors_count             dd 0

; Extended Boot Record
ebr_drive_number                    db 0
ebr_flags                           db 0
ebr_signature                       db 29h
ebr_volume_id                       dd 99999999h
ebr_volume_label                    db "MY_OS_VOL  "
ebr_file_system_type                db "FAT12   "


;
;    Code start here
;

start:
    jmp main

;
;   Prints a string to screen
;   Params:
;       ds/si points to string
;

puts:
    push si                 ; push register where pointer is si
    push ax                 ; save register al for lodsb
.loop: 
    lodsb
    cmp al, 0
    je .done
    mov ah, 00eh
    mov bh, 0
    int 010h
    jmp .loop
.done:
    pop ax
    pop si
    ret


main:
    mov ax, 0
    ; setup segments registers
    mov ds, ax
    mov ss, ax
    mov es, ax

    ; setup stack pointer to 0x7C00, because it write downwards
    mov sp, 07C00h

    ; print data
    mov si, data            ; put the address of data into si register
    call puts               ; call puts function

    ; exit
    jmp $

data:
    db "HELLO, WORLD!", ENDL, 0

times 510-($-$$) db 0
dw 0aa55h