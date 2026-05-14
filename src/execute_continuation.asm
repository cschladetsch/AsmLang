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
extern context_counts
extern context_scope_values
extern context_scope_types
extern continuation_signal
extern buffer
extern output_buffer
extern string_offset

section .text

global execute_continuation_impl
global execute_continuation_tail
global push_context
global pop_context
global format_stack_slice
global collapse_stack_slice_to_array

; -----------------------------------------------------------------------
; execute_continuation_impl
; rdi = literal index
; Assumes caller scope has already been pushed with push_context.
; Loads continuation scope, executes body, restores caller scope.
; -----------------------------------------------------------------------
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

    ; load captured literal scope into variables/var_types
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

    ; copy literal body into input buffer (strip braces)
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
    mov rdi, [rel active_op_list]
    mov rsi, r13
    call translate
    mov rsi, rax
    mov rdi, [rel active_bytecode]   ; dereference: get actual bytecode array address
    movzx r14d, byte [rel in_continuation]
    mov byte [rel in_continuation], 1
    call execute
    mov byte [rel in_continuation], r14b

    ; clear continuation signals after the nested executor exits
    cmp qword [rel continuation_signal], CONT_SIGNAL_NONE
    je .restore
    mov qword [rel continuation_signal], CONT_SIGNAL_NONE
.restore:
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

; -----------------------------------------------------------------------
; execute_continuation_tail
; rdi = literal index
; Like execute_continuation_impl but NO push_context/pop_context.
; Used by '!' (replace) for tail-call semantics -- no frame growth.
; Loads captured scope, executes body, leaves scope as-is on return.
; -----------------------------------------------------------------------
execute_continuation_tail:
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

    ; load captured literal scope (no push_context)
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
    mov rdi, [rel active_op_list]
    mov rsi, r13
    call translate
    mov rsi, rax
    mov rdi, [rel active_bytecode]   ; dereference: get actual bytecode array address
    movzx r14d, byte [rel in_continuation]
    mov byte [rel in_continuation], 1
    call execute
    mov byte [rel in_continuation], r14b

    ; clear any signal (tail-call absorbs it)
    mov qword [rel continuation_signal], CONT_SIGNAL_NONE

    ; restore active workspace pointers (no pop_context)
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

; -----------------------------------------------------------------------
; push_context
; Saves current variables/var_types onto the context stack.
; Returns rax = 0 on success, -1 on overflow.
; -----------------------------------------------------------------------
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
    lea rax, [rel context_counts]
    mov [rax + rbx*8], rdi
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

; -----------------------------------------------------------------------
; format_stack_slice
; rdi = start depth
; returns rax = raw-literal header pointer, formatted as "[a, b]"
; -----------------------------------------------------------------------
format_stack_slice:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    lea r8, [rel buffer]
    mov byte [r8], '['
    inc r8
    mov r12, rdi
    mov r13, [rel stack_top]

.item_loop:
    cmp r12, r13
    jge .finish
    cmp r12, rdi
    je .no_sep
    mov byte [r8], ','
    inc r8
    mov byte [r8], ' '
    inc r8
.no_sep:
    mov rax, [rel stack + r12*8]
    movzx edx, byte [rel stack_types + r12]
    cmp edx, TYPE_NUM
    je .append_num
    cmp edx, TYPE_LABEL
    je .append_num
    cmp edx, TYPE_STR
    je .append_str
    cmp edx, TYPE_ARRAY
    je .append_array
    cmp edx, TYPE_CONT
    je .append_cont
    cmp edx, TYPE_BOOL
    je .append_bool
    jmp .next_item

.append_num:
    mov r14, rax
    test r14, r14
    jns .num_positive
    mov byte [r8], '-'
    inc r8
    neg r14
.num_positive:
    lea rbx, [rel output_buffer + 31]
    mov rcx, 0
    mov rax, r14
    mov r9, 10
.num_loop:
    xor rdx, rdx
    div r9
    add dl, '0'
    dec rbx
    mov [rbx], dl
    inc rcx
    test rax, rax
    jnz .num_loop
    mov rsi, rbx
.num_copy:
    test rcx, rcx
    jz .next_item
    mov al, [rsi]
    mov [r8], al
    inc r8
    inc rsi
    dec rcx
    jmp .num_copy

.append_str:
    mov byte [r8], '"'
    inc r8
    mov r10, [rax]
    lea r11, [rax + 8]
.str_loop:
    test r10, r10
    jz .str_close
    mov bl, [r11]
    mov [r8], bl
    inc r8
    inc r11
    dec r10
    jmp .str_loop
.str_close:
    mov byte [r8], '"'
    inc r8
    jmp .next_item

.append_array:
    mov r10, [rax]
    lea r11, [rax + 8]
.array_loop:
    test r10, r10
    jz .next_item
    mov bl, [r11]
    mov [r8], bl
    inc r8
    inc r11
    dec r10
    jmp .array_loop

.append_cont:
    mov byte [r8], '<'
    inc r8
    mov byte [r8], 'c'
    inc r8
    mov byte [r8], 'o'
    inc r8
    mov byte [r8], 'n'
    inc r8
    mov byte [r8], 't'
    inc r8
    mov byte [r8], '>'
    inc r8
    jmp .next_item

.append_bool:
    cmp rax, 0
    je .bool_false
    mov byte [r8], 't'
    inc r8
    mov byte [r8], 'r'
    inc r8
    mov byte [r8], 'u'
    inc r8
    mov byte [r8], 'e'
    inc r8
    jmp .next_item
.bool_false:
    mov byte [r8], 'f'
    inc r8
    mov byte [r8], 'a'
    inc r8
    mov byte [r8], 'l'
    inc r8
    mov byte [r8], 's'
    inc r8
    mov byte [r8], 'e'
    inc r8

.next_item:
    inc r12
    jmp .item_loop

.finish:
    mov byte [r8], ']'
    inc r8
    mov byte [r8], 0
    lea rsi, [rel buffer]
    call store_raw_literal
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------
; collapse_stack_slice_to_array
; rdi = start depth
; Replace stack[start:] with a single TYPE_ARRAY entry containing
; the textual snapshot of that slice.
; -----------------------------------------------------------------------
collapse_stack_slice_to_array:
    push rbp
    mov rbp, rsp
    push r12

    mov r12, rdi
    call format_stack_slice
    mov [rel stack_top], r12
    mov rdi, rax
    mov rsi, TYPE_ARRAY
    call push_type

    pop r12
    leave
    ret

; -----------------------------------------------------------------------
; pop_context
; Restores variables/var_types from the context stack.
; Returns rax = 0 on success, -1 if stack empty.
; -----------------------------------------------------------------------
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
