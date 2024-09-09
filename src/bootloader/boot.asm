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
    mov ax, 0
    ; setup segments registers
    mov ds, ax
    mov es, ax
    mov ss, ax
    ; setup stack
    mov sp, 07C00h                                  ; setup stack pointer to 0x7C00, because it write downwards
    mov bp, sp

    push es                                         ; push es register to stack
    push word .main                                 ; push ip register to stack
    retf                                            ; pop both es and ip register => we will start from 0000:7C00, some bioses may set us at 7C00:0000
.main:
    ; print start message
    mov si, start_msg
    call puts

    ; read drive parameter from BIOS
    push es
    mov [ebr_drive_number], dl                      ; BIOS should set dl to the drive number
    xor di, di                                      ; set es:di to 0000h:0000h to work around some buggy BIOS
    mov ah, 08h
    int 013h                                        ; interupt 013h, 08h to read drive parameters
    jc disk_error
    pop es                                          ; it may broke es after interupt 013h, 08h

    inc dh
    mov [bpb_heads_count], dh

    xor ch, ch
    and cl, 037h
    mov [bpb_sectors_per_track_count], cx

    ; Calculate the LBA of root directory entries
    mov ax, [bpb_sectors_per_FAT_count]
    mul byte [bpb_FATs_count]
    add ax, [bpb_reserved_sectors_count]
    push ax

    ; Calculate number of sectors of root directory entries
    mov ax, [bpb_root_directory_entry_count]
    shl ax, 5                                       ; ax = (root_directory_entries * 32)
    xor dx, dx                                      ; clean dx register
    div word [bpb_bytes_per_sector]                 ; ax = (root_directory_entries * 32) / bytes_per_sector and dx = (root_directory_entries * 32) % bytes_per_sector
    test dx, dx                                     ; if dx != 0 then ax += 1
    jz .root_dir_entries_after
    inc ax
.root_dir_entries_after:
    mov cx, ax
    pop ax
    push cx                                         ; save the number of sectors of root directory entries
    mov dl, [ebr_drive_number]
    mov bx, 07E00h                                  ; data should be after the bootloader
    call disk_load

    ; Find the kernel in the root directory
    mov ax, [bpb_root_directory_entry_count]
.loop_search_kernel:
    test ax, ax
    jz .not_found_kernel
    mov cx, 11
    mov si, bx
    mov di, kernel_bin
    repe cmpsb
    je .found_kernel
    add bx, 32
    dec ax
    test ax, ax
    jz .not_found_kernel
    jmp .loop_search_kernel

.found_kernel:
    mov ax, [bx + 26]                               ; ax = first cluster number
    mov [kernel_cluster], ax
    
    ; read FAT
    mov ax, [bpb_reserved_sectors_count]            ; ax = LBA = 1
    mov dl, [ebr_drive_number]                      ; dl = drive number
    mov cx, [bpb_sectors_per_FAT_count]             ; cl = sector to read
    mov bx, 07E00h                                  ; data should be after the bootloader
    call disk_load

    mov bx, KERNEL_SEGMENT
    mov es, bx
    mov bx, KERNEL_OFFSET                           ; we will set es:bx to 09000h:0000h and store the kernel there
    ; mov bx, 09000h
    ; read kernel.bin and process FAT chain
.read_kernel:
    mov ax, [kernel_cluster]
    add ax, 31                                      ; as we know LBA = (cluster - 2)*sector_per_cluster + data_LBA. I have to hardcode this because calculate it may exceed 512 bytes
                                                    ; data_LBA = reserver_sectors + FAT_counts * sectors_per_FAT + sectors of root directory entries
    mov dl, [ebr_drive_number]                      ; dl = drive number
    mov cl, [bpb_sectors_per_cluster]               ; cl = sector to read
    call disk_load
    add bx, [bpb_bytes_per_sector]                  ; bx += bpb_sectors_per_cluster * bpb_bytes_per_sector = bpb_bytes_per_sector

    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    xor dx, dx
    mov cx, 2
    div cx                                          ; ax = kernel_cluster * 3 / 2, dx = kernel_cluster * 3 % 2

    mov si, 07E00h
    add si, ax
    mov ax, [ds:si]
    
    test dx, dx
    jz .even
.odd:
    shr ax, 4
.even:
    and ax, 0FFFh
    jmp .condition
.condition:
    mov [kernel_cluster], ax
    cmp ax, 0FF8h
    jb .read_kernel
.kernel_loaded:
    mov dl, [ebr_drive_number]
    mov ax, KERNEL_SEGMENT                          ; set segment registers
    mov ds, ax
    mov es, ax
    jmp KERNEL_SEGMENT:KERNEL_OFFSET
    jmp wait_key_and_reboot                         ; should never happen
    cli                                             ; disable interrupts
    hlt
    
.not_found_kernel:
    mov si, not_found_kernel_msg
    call puts
    jmp wait_key_and_reboot
    hlt
.halt:
    jmp .halt
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
    jmp wait_key_and_reboot
wait_key_and_reboot:
    mov ah, 0
    int 016h
    jmp 0FFFFh:0
.halt:
    cli
    hlt

start_msg: db "loading...", ENDL, 0

floppy_fail_msg: db "Cannot read Disk", 0

kernel_bin: db "KERNEL  BIN"

not_found_kernel_msg: db "Cannot find KERNEL.BIN", 0

kernel_cluster: dw 0

KERNEL_SEGMENT equ 09000h
KERNEL_OFFSET  equ 0

times 510-($-$$) db 0
dw 0AA55h