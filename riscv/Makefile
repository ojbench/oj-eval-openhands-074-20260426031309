prefix = $(shell pwd)
# Folder Path
src = $(prefix)/src
testspace = $(prefix)/testspace

sim_testcase = $(prefix)/testcase/sim
fpga_testcase = $(prefix)/testcase/fpga

sim = $(prefix)/sim
riscv_toolchain = $(prefix)/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14
riscv_bin = $(riscv_toolchain)/bin
sys = $(prefix)/sys

_no_testcase_name_check:
	@$(if $(strip $(name)),, echo 'Missing Testcase Name')
	@$(if $(strip $(name)),, exit 1)

# All build result are put at testspace
build_sim:
	@cd $(src) && iverilog -o $(testspace)/test $(sim)/testbench.v $(src)/common/block_ram/*.v $(src)/common/fifo/*.v $(src)/common/uart/*.v $(src)/*.v

build_sim_test: _no_testcase_name_check
	@$(riscv_bin)/riscv64-unknown-elf-as -o $(sys)/rom.o -march=rv32i $(sys)/rom.s
	@cp $(sim_testcase)/*$(name)*.c $(testspace)/test.c
	@$(riscv_bin)/riscv64-unknown-elf-gcc -o $(testspace)/test.o -I $(sys) -c $(testspace)/test.c -O2 -march=rv32i -mabi=ilp32 -Wall
	@$(riscv_bin)/riscv64-unknown-elf-gcc -nostdlib -nostartfiles -T $(sys)/memory.ld $(sys)/rom.o $(testspace)/test.o -o $(testspace)/test.om
	@$(riscv_bin)/riscv64-unknown-elf-objcopy -O verilog $(testspace)/test.om $(testspace)/test.data
	@$(riscv_bin)/riscv64-unknown-elf-objdump -D $(testspace)/test.om > $(testspace)/test.dump

run_sim:
	@cd $(testspace) && ./test

clear:
	@rm $(sys)/rom.o $(testspace)/test*

test_sim: build_sim build_sim_test run_sim

.PHONY: _no_testcase_name_check build_sim build_sim_test run_sim clear test_sim
