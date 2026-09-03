%include "constants.inc"

extern stack
extern stack_top
extern stack_types
extern output_buffer
extern cont_storage
extern cont_storage_offset
section .text

global push_num
global push_str
global push_type
global pop
global pop_num
global pop_bool

push_num:
    mov rcx, [stack_top]
    cmp rcx, 10000
    jge .overflow
    mov [stack + rcx*8], rax
    mov byte [stack_types + rcx], TYPE_NUM
    inc rcx
    mov [stack_top], rcx
    ret
.overflow:
    ret

push_str:
    mov rcx, [stack_top]
    cmp rcx, 10000
    jge .overflow
    mov [stack + rcx*8], rax
    mov byte [stack_types + rcx], TYPE_STR
    inc rcx
    mov [stack_top], rcx
    ret
.overflow:
    ret

push_type:
    mov rcx, [stack_top]
    cmp rcx, 10000
    jge .overflow
    mov [stack + rcx*8], rdi
    mov byte [stack_types + rcx], sil
    inc rcx
    mov [stack_top], rcx
    ret
.overflow:
    ret

pop:
    mov rcx, [stack_top]
    test rcx, rcx
    jz .underflow
    dec rcx
    mov [stack_top], rcx
    mov rax, [stack + rcx*8]
    movzx edx, byte [stack_types + rcx]
    ret
.underflow:
    mov rax, 1
    mov rdi, 1
    mov rsi, .msg
    mov rdx, .msg_len
    syscall
    mov rax, 0
    mov rdx, 0
    ret
.msg db "Stack underflow", 10
.msg_len equ $ - .msg

pop_num:
    call pop
    cmp edx, TYPE_NUM
    je .ok
    mov rax, 0
    ret
.ok:
    ret

pop_bool:
    call pop
    cmp edx, TYPE_BOOL
    je .ok
    mov rax, 0
    ret
.ok:
    ret
global collapse_stack_slice_to_array
collapse_stack_slice_to_array:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi
    mov r13, [stack_top]

    mov rbp, [cont_storage_offset]
    lea r14, [cont_storage + rbp]
    add rbp, 8
    mov r15, rbp

    mov byte [cont_storage + rbp], '['
    inc rbp
    mov byte [cont_storage + rbp], ' '
    inc rbp

    mov rbx, r12
.cssa_item_loop:
    cmp rbx, r13
    jge .cssa_done_items

    mov rax, [stack + rbx*8]
    movzx ecx, byte [stack_types + rbx]

    cmp ecx, TYPE_NUM
    je .cssa_fmt_num
    cmp ecx, TYPE_BOOL
    je .cssa_fmt_bool
    cmp ecx, TYPE_STR
    je .cssa_fmt_bytes
    cmp ecx, TYPE_ARRAY
    je .cssa_fmt_bytes
    jmp .cssa_sep

.cssa_fmt_num:
    mov r10, rax
    test r10, r10
    jns .cssa_positive
    neg r10
    mov byte [cont_storage + rbp], '-'
    inc rbp
.cssa_positive:
    lea rsi, [output_buffer]
    xor r11, r11
.cssa_digit_loop:
    xor edx, edx
    mov rax, r10
    mov rcx, 10
    div rcx
    mov r10, rax
    add dl, '0'
    mov [rsi + r11], dl
    inc r11
    test r10, r10
    jnz .cssa_digit_loop
    dec r11
.cssa_copy_digits:
    mov al, [rsi + r11]
    mov [cont_storage + rbp], al
    inc rbp
    dec r11
    jns .cssa_copy_digits
    jmp .cssa_sep

.cssa_fmt_bool:
    cmp rax, 1
    je .cssa_true
    mov r10, 5
    lea rsi, [rel .cssa_false_str]
    jmp .cssa_copy_lit
.cssa_true:
    mov r10, 4
    lea rsi, [rel .cssa_true_str]
.cssa_copy_lit:
    xor r11, r11
.cssa_copy_lit_loop:
    cmp r11, r10
    jge .cssa_sep
    mov al, [rsi + r11]
    mov [cont_storage + rbp], al
    inc rbp
    inc r11
    jmp .cssa_copy_lit_loop

.cssa_fmt_bytes:
    mov r10, [rax]
    lea rsi, [rax + 8]
    xor r11, r11
.cssa_copy_bytes:
    cmp r11, r10
    jge .cssa_sep
    mov al, [rsi + r11]
    mov [cont_storage + rbp], al
    inc rbp
    inc r11
    jmp .cssa_copy_bytes

.cssa_sep:
    mov byte [cont_storage + rbp], ' '
    inc rbp

    inc rbx
    jmp .cssa_item_loop

.cssa_done_items:
    mov byte [cont_storage + rbp], ']'
    inc rbp

    mov rax, rbp
    sub rax, r15
    mov [r14], rax

    add rbp, 7
    and rbp, ~7
    mov [cont_storage_offset], rbp

    mov qword [stack_top], r12

    mov rdi, r14
    mov sil, TYPE_ARRAY
    call push_type

    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.cssa_false_str db "false"
.cssa_true_str  db "true"
