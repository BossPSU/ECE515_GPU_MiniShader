module martian_days (M, LY, D27, D28);

input [4:0] M; //encoded value for month vector
input LY; //leap year

//output 1 for D27 if month has 27 days
//output 1 for D28 if month has 28 days
output D27,D28;

//continuous assignment
assign #6 D27 = ~M[0] | (M[4] & ~M[3] & M[2] & M[1] & M[0] & ~LY);

assign #6 D28 = M[0] | (M[4] & M[3] & ~M[2] & ~M[1] & ~M[0] & LY);

endmodule
