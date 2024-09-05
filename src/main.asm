org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

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
    mov ah, 0x0e
    mov bh, 0
    int 0x10
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
    mov sp, 0x7C00

    ; print data
    mov si, data            ; put the address of data into si register
    call puts               ; call puts function

    ; exit
    jmp $

data:
    db "HELLO, WORLD!", ENDL, 0

times 510-($-$$) db 0
dw 0xaa55