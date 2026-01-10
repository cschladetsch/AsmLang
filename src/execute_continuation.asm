section .text
%include "constants.inc"

extern cont_literal_offsets
extern cont_literal_lengths
extern cont_literal_values
extern cont_literal_types
extern cont_input_buffer
extern cont_storage
extern cont_build_buffer
extern cont_token_ptrs
extern cont_token_meta
extern cont_op_list
extern cont_bytecode
extern active_token_ptrs
extern active_token_meta
extern active_op_list
extern active_bytecode
extern tokenize
extern parse_tokens
extern translate
extern execute
extern variables
extern var_types
extern stack
extern stack_top
extern stack_types
extern store_raw_literal
extern in_continuation
extern context_stack_top
extern context_scope_values
extern context_scope_types

section .text

global execute_continuation_impl
global push_context
global pop_context

execute_continuation_impl:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8
    push r9
    push r10
    mov r15, rdi                ; literal index

    ; save active work buffers and switch to continuation workspace
    push qword [rel active_token_ptrs]
    push qword [rel active_token_meta]
    push qword [rel active_op_list]
    push qword [rel active_bytecode]
    lea rax, [rel cont_token_ptrs]
    mov [rel active_token_ptrs], rax
    lea rax, [rel cont_token_meta]
    mov [rel active_token_meta], rax
    lea rax, [rel cont_op_list]
    mov [rel active_op_list], rax
    lea rax, [rel cont_bytecode]
    mov [rel active_bytecode], rax

    ; capture caller scope
    call push_context

    ; load captured literal scope
    mov rax, r15
    mov rcx, VAR_SLOT_COUNT*8
    imul rax, rcx
    lea rsi, [rel cont_literal_values]
    add rsi, rax
    lea rdi, [rel variables]
    mov rcx, VAR_SLOT_COUNT
    rep movsq
    mov rax, r15
    mov ecx, VAR_SLOT_COUNT
    imul rax, rcx
    lea rsi, [rel cont_literal_types]
    add rsi, rax
    lea rdi, [rel var_types]
    mov rcx, VAR_SLOT_COUNT
    rep movsb

    ; copy literal body into input buffer
    lea rax, [rel cont_literal_offsets]
    mov r10, [rax + r15*8]
    lea rdx, [rel cont_literal_lengths]
    mov ecx, [rdx + r15*4]
    lea rsi, [rel cont_storage]
    add rsi, r10
    lea rbx, [rel cont_input_buffer]
    mov rdi, rbx
    mov r8, rcx
    rep movsb
    mov byte [rdi], 0

    ; tokenize, parse, translate, execute
    lea rsi, [rel cont_input_buffer]
    call tokenize
    mov r12, rax
    lea rdi, [rel active_token_ptrs]
    mov rsi, r12
    call parse_tokens
    mov r13, rax
    lea rdi, [rel active_op_list]
    mov rsi, r13
    lea rdx, [rel active_bytecode]
    call translate
    mov rsi, rax
    lea rdi, [rel active_bytecode]
    movzx r14d, byte [rel in_continuation]
    mov byte [rel in_continuation], 1
    call execute
    mov byte [rel in_continuation], r14b

    ; restore caller scope
    call pop_context

    ; restore active workspace pointers
    pop rax
    mov [rel active_bytecode], rax
    pop rax
    mov [rel active_op_list], rax
    pop rax
    mov [rel active_token_meta], rax
    pop rax
    mov [rel active_token_ptrs], rax

    pop r10
    pop r9
    pop r8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

push_context:
    push rbp
    mov rbp, rsp
    push rbx
    lea rax, [rel context_stack_top]
    mov rbx, [rax]
    inc rbx
    cmp rbx, CONTEXT_STACK_MAX
    jae .overflow
    mov [rax], rbx
    ; copy variable values
    lea rsi, [rel variables]
    lea rdi, [rel context_scope_values]
    mov rcx, VAR_SLOT_COUNT
    mov rdx, VAR_SLOT_COUNT*8
    mov r8, rbx
    imul r8, rdx
    add rdi, r8
    rep movsq
    ; copy types
    lea rsi, [rel var_types]
    lea rdi, [rel context_scope_types]
    mov rcx, VAR_SLOT_COUNT
    mov rdx, VAR_SLOT_COUNT
    mov r8, rbx
    imul r8, rdx
    add rdi, r8
    rep movsb
    xor rax, rax
    jmp .done
.overflow:
    mov rax, -1
.done:
    pop rbx
    leave
    ret

pop_context:
    push rbp
    mov rbp, rsp
    push rbx
    lea rax, [rel context_stack_top]
    mov rbx, [rax]
    cmp rbx, -1
    je .empty
    ; restore values
    lea rsi, [rel context_scope_values]
    mov rcx, VAR_SLOT_COUNT
    mov rdx, VAR_SLOT_COUNT*8
    mov r8, rbx
    imul r8, rdx
    add rsi, r8
    lea rdi, [rel variables]
    rep movsq
    ; restore types
    lea rsi, [rel context_scope_types]
    mov rcx, VAR_SLOT_COUNT
    mov rdx, VAR_SLOT_COUNT
    mov r8, rbx
    imul r8, rdx
    add rsi, r8
    lea rdi, [rel var_types]
    rep movsb
    dec rbx
    mov [rax], rbx
    xor rax, rax
    jmp .done
.empty:
    mov rax, -1
.done:
    pop rbx
    leave
    ret
