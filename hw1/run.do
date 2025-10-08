vlog martian_days.sv martian_days_tb.sv
vopt work.top -o top_opt +acc
vsim top_opt
add wave *
run -all
