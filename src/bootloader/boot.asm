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
ebr_signature                       db 029h
ebr_volume_id                       dd 099999999h
ebr_volume_label                    db "MY_OS_VOL  "
ebr_file_system_type                db "FAT12   "


;
;    Code start here
;

start:
    jmp main

;
;   Ultilities
;

;
;   Prints a string to screen
;   Params:
;       ds/si - points to string
;

puts:
    push si                                         ; save register si
    push ax                                         ; save register al, ah
    push bx                                         ; save register bh
.loop: 
    lodsb
    test al, al                                     ; this will trigger ZF if al = 0
    jz .done
    mov ah, 0Eh
    mov bh, 0
    int 010h
    jmp .loop
.done:
    pop bx
    pop ax
    pop si
    ret

;
;   Prints a number to screen
;   Params:
;       ax - a number
;

print_num:
    push ax                                         ; save register ax
    push bx                                         ; save register bx
    push cx                                         ; save register cx
    push dx                                         ; save register dx
    mov cx, 0
.loop:
    xor dx, dx                                      ; clean dx register
    mov bx, 10
    div word bx                                     ; ax = ax / 10 and dx = ax % 10
    add dx, 48                                      ; dx = dx + '0'
    push dx                                         ; push dx to stack
    inc cx                                          ; cx = cx + 1
    test ax, ax                                     ; this will trigger ZF if ax = 0
    jnz .loop
    mov ah, 0Eh
    mov bh, 0
.print:
    test cx, cx                                     ; if cx = 0 then done
    jz .done
    dec cx                                          ; cx = cx - 1
    pop dx                                          ; pop stack to dx
    mov al, dl                                      ; al = dl
    int 010h
    jmp .print
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

;
;   Convert LBA to CHS
;   Params:
;       ax - logical block address
;   Returns:
;       cx (bit 6 - 15) - cylinder number
;       cx (bit 0 - 5)  - sector number
;       dh              - head number
;


lba_to_chs:
    push ax                                         ; save register ax
    push dx                                         ; save register dx because we only modify and return the dh

    xor cx, cx                                      ; clean cx register
    xor dx, dx                                      ; clean dx register
    div word [bpb_sectors_per_track_count]          ; ax = LBA / SPT and dx = LBA % SPT
    inc dx                                          ; dx = LBA % SPT + 1 = sector number
    mov cl, dl                                      ; cx = dx = sector number

    xor dx, dx                                      ; clean dx register
    div word [bpb_heads_count]                      ; ax = ax / HPC = cylinder number and dx = ax % HPC = head number
    mov dh, dl                                       ; dh = head number

    mov ch, al                                      ; ch = al, ch is the lower order bit of ax
    shl ah, 6                                       ; ax << 6 -> ax000000
    or cl, ah                                       ; cx = ax | cx => combine the 2 high order bit of cylinder number and sector number

    pop ax                                          ; recover the dl
    mov dl, al 
    pop ax
    ret
;
;   Disk routine
;

;
;   Load Disk sectors
;   Params:
;       ax    - logical block address
;       cl    - number of sectors to read (1-128)
;       dl    - drive number
;       es:bx - pointer to buffer
;

disk_load:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax
    mov ah, 02h
    mov di, 3
.retry:
    pusha
    stc
    int 013h
    jnc .done
    popa
    call disk_reset
    dec di
    test di, di
    jnz .retry
.fail:
    jmp disk_error
.done:
    popa
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    cli                                             ; not doing this will make the system still stuck in the interrupt
    ret

;
;   Reset Disk
;   Params:
;       dl - drive number
;

disk_reset:
    pusha
    mov ah, 0
    stc
    int 013h
    jc disk_error
    popa
    ret
;
;   Hanlding Disk Reading Error
;

disk_error:
    mov si, floppy_fail_msg
    call puts
    mov ah, 0
    int 016h
    jmp 0FFFFh:0
.halt:
    cli
    htl

main:
    mov ax, 0
    ; setup segments registers
    mov ds, ax
    mov ss, ax
    mov es, ax

    ; setup stack pointer to 0x7C00, because it write downwards
    mov sp, 07C00h

    ; read disk
    mov [ebr_drive_number], dl  ; BIOS should set dl to the drive number
    mov ax, 1                   ; LBA=1, second sector from disk
    mov cl, 1                   ; 1 sector to read
    mov bx, 0x7E00              ; data should be after the bootloader
    call disk_load
    
    ; print data
    mov si, data            ; put the address of data into si register
    call puts               ; call puts function

    mov si, new_line
    mov ax, [0x7E00]        ; this is the ofset of 200 from 0x7C00, and in the disk, this will be 0xF0FF which in little endian is 65520
    call print_num          ; print out 65520
    call puts               ; print new line
    ; exit
    jmp $

new_line: db ENDL, 0

data: db "HELLO, WORLD!", ENDL, 0

floppy_fail_msg: db "Cannot read floppy, press any button to restart...", ENDL, 0

times 510-($-$$) db 0
dw 0AA55h