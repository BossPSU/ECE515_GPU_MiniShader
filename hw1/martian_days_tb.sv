//behavioral TB
module top();
reg [4:0] M;
reg LY;
wire D27,D28;

//instantiate DUT
martian_days D1 (M,LY,D27,D28);

initial
	begin
		for(M=0; M<=23;M=M+1)
			begin
				LY=0; #10;
				LY=1; #10;
			end
			$finish();
	end
endmodule
