section .data
temp times 21 db 0
newline db 10
prompt_prefix db 0xCE, 0xBB, ' '
prompt_prefix_len equ $ - prompt_prefix
quote_char db '"'
minus_char db '-'
open_bracket db '['
close_bracket_colon db ']: '
close_bracket_colon_len equ $ - close_bracket_colon

section .text
extern stack
extern stack_top
extern stack_types
extern stdin_is_tty
extern cont_literal_offsets
extern cont_literal_lengths
extern cont_storage

global print_stack

print_stack:
    push rbx
    push r12
    
    cmp byte [stdin_is_tty], 0
    jne .no_batch_prompt
    mov rax, 1
    mov rdi, 1
    lea rsi, [prompt_prefix]
    mov rdx, prompt_prefix_len
    syscall
.no_batch_prompt:
    mov r12, [stack_top]
    test r12, r12
    jz .done
    dec r12

.loop:
    ; Print [
    mov rax, 1
    mov rdi, 1
    lea rsi, [open_bracket]
    mov rdx, 1
    syscall

    ; Print index
    mov rax, r12
    call print_number

    ; Print ]: 
    mov rax, 1
    mov rdi, 1
    lea rsi, [close_bracket_colon]
    mov rdx, close_bracket_colon_len
    syscall

    ; Get value and type
    mov rax, [stack + r12*8]
    movzx edx, byte [stack_types + r12]

    cmp edx, TYPE_NUM
    je .print_num
    cmp edx, TYPE_LABEL
    je .print_num
    cmp edx, TYPE_STR
    je .print_str
    cmp edx, TYPE_BOOL
    je .print_bool
    cmp edx, TYPE_ARRAY
    je .print_array
    cmp edx, TYPE_CONT
    je .print_cont
    jmp .next_item

.print_num:
    call print_number
    jmp .next_item

.print_str:
    mov r10, [rax]          ; length
    lea r9, [rax + 8]       ; data pointer
    mov rax, 1
    mov rdi, 1
    lea rsi, [quote_char]
    mov rdx, 1
    syscall
    mov rax, 1
    mov rdi, 1
    mov rsi, r9
    mov rdx, r10
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [quote_char]
    mov rdx, 1
    syscall
    jmp .next_item

.print_bool:
    cmp rax, 1
    je .true
    mov rsi, .false
    mov rdx, .false_len
    jmp .print
.true:
    mov rsi, .true_str
    mov rdx, .true_len
.print:
    mov rax, 1
    mov rdi, 1
    syscall
    jmp .next_item
.false db "false"
.false_len equ $ - .false
.true_str db "true"
.true_len equ $ - .true_str

.print_array:
    mov r10, [rax]
    lea r9, [rax + 8]
    mov rax, 1
    mov rdi, 1
    mov rsi, r9
    mov rdx, r10
    syscall
    jmp .next_item

.print_cont:
    mov r11, rax          ; literal index
    lea rsi, [cont_literal_offsets]
    mov rax, [rsi + r11*8]
    lea r9, [cont_storage]
    add r9, rax
    lea rsi, [cont_literal_lengths]
    mov r10d, [rsi + r11*4]
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel .open_cont]
    mov rdx, .open_cont_len
    syscall
    mov rax, 1
    mov rdi, 1
    mov rsi, r9
    mov rdx, r10
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel .close_cont]
    mov rdx, .close_cont_len
    syscall
    jmp .next_item
.open_cont db '{'
.open_cont_len equ $ - .open_cont
.close_cont db '}'
.close_cont_len equ $ - .close_cont

.next_item:
    mov rax, 1
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall
    
    dec r12
    jns .loop

.done:
    pop r12
    pop rbx
    ret

print_number:
    test rax, rax
    jns .positive
    neg rax
    push rax
    mov rax, 1
    mov rdi, 1
    lea rsi, [minus_char]
    mov rdx, 1
    syscall
    pop rax
.positive:
    mov rbx, 10
    lea rdi, [temp + 20]
    mov rcx, 0
.loop_num:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc rcx
    test rax, rax
    jnz .loop_num
    mov rax, 1
    mov rsi, rdi
    mov rdx, rcx
    mov rdi, 1
    syscall
    ret
