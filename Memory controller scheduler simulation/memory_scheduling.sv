import timing_parameters::*;

module memory_scheduling#(parameter ENABLE_TEST=0);
int file_read;   // file handler for read
int file_write;  // to write into output trace file
int read_value; 
int  time_unit;
logic [11:0] core;
logic [1:0] operation;
logic [35:0] address;
string input_file, output_file;
longint unsigned time_t=1;
// full & empty conditions
int full_qu, empty_qu;
int simulation_t;
// Bounded queue
logic [37:0] q_memctrl[$:15];
longint unsigned q_time[$];
int q_oper[$];
logic [35:0] q_addr[$];
logic [37:0] output_data,temp;
//counter
int count;
int ACT, RD, WR, PRE, DONE;
int dimm_time;
always #1 time_t = time_t + 1;

// Parsing input trace file
task parsing();
  int i; read_value=0;
  $display("Reading and printing values from input trace file");   
  if($value$plusargs("input_file=%s",input_file))begin
  //Read a input trace file through command line
    file_read =$fopen(input_file,"r");
    if(file_read == 0) begin
      if(ENABLE_TEST) 
        $display("trace file not found read");
      end        
      while (1) begin
      // Read values from the file		
        read_value = $fscanf(file_read, "%d %d %d %h", time_unit, core, operation, address);
	if(core>=12 || operation >=3) begin 
          $display(" Trace file has out of bound values");
	  $finish;
	end
        if (read_value == 4) begin
          if(ENABLE_TEST) $display("the value of time=%0d, core=%0d, operation=%0h, address=%0h ", time_unit, core, operation, address); 
          q_oper.push_back(operation);
	  q_addr.push_back(address);
	  q_time.push_back(time_unit);
          i++;
        end          
        else begin
          break; // exit after the last line
        end                  
      end
      $fclose(file_read);      
    end
    else begin
      $display("error :please provide the input file using +input_file=<filename>");
    end
    $display("End of Parsing task");  
endtask

//Push each element to master queue
task mem_ctrl_store(); 
  temp = {q_oper.pop_front(), q_addr.pop_front()};
  q_memctrl.push_back(temp);
  if(ENABLE_TEST) $display("Push new item to master queue(memctrl) queue=%0h, CPU_Time=%0d,memctrl_q_size=%0d", temp,time_t,q_memctrl.size);
endtask

// pop out each element from master queue
task toggle_out_from_memctrl_q();
  output_data= q_memctrl[0];
  output_cmd_format(output_data);
  q_memctrl.pop_front();
  if(output_data || (output_data==0)) begin 
    if(ENABLE_TEST) 
      $display("Pop out item from queue output_data =%0h, DIMM_time=%0d, q_mem_ctrl_size=%0d \n", output_data,time_t,q_memctrl.size());
      $display("-----------------------------------END--------------------------------------------------------------------------------\n");
  end
  count++;
endtask

// Address decoding logic 
task output_cmd_format(input [37:0] output_data);
if(ENABLE_TEST) begin
    if($value$plusargs("output_file=%s",output_file))begin
  file_write=$fopen(output_file,"a");// opening file in append mode
  if(file_write!=0) begin

     // READ OPERATIONS
    if(output_data[37:36] ==0 || output_data[37:36]==2) begin
      $display("---------------READ OPERATION------------------------------OPERATION=%d----------------------------------", output_data[37:36]);
      // DRIVE ACT COMMANDS
      if(ACT==0) begin
        dimm_time = time_t;
        wait(dimm_time <= time_t);
        $display(" %t \t channel=%d, ACT0 bank_group=%d, bank=%d, row=%h", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        $fwrite(file_write,"%8t \t %d\t ACT0 %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        wait(dimm_time+2 <= time_t);
        $display(" %t \t channel=%d, ACT1 bank_group=%d, bank=%d, row=%h", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        $fwrite(file_write,"%8t \t %d\t ACT1 %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        ACT = 1; dimm_time = dimm_time + 2;
      end
      
      // DRIVE READ COMMANDS     
      if((ACT==1) && (RD==0)) begin
        wait(dimm_time + tRCD <= time_t);
        $display(" %t \t channel=%d, RD0 bank_group=%d, bank=%d, column=%h", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        $fwrite(file_write,"%8t \t %d\t RD0  %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        wait(dimm_time + tRCD + 2 <= time_t);
        $display(" %t \t channel=%d, RD1 bank_group=%d, bank=%d, column=%h", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12],output_data[5:2]});
        $fwrite(file_write,"%8t \t %d\t RD1  %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        RD=1; dimm_time = dimm_time + tRCD + 2;
      end

      // DRIVE PRE COMMAND
      if((ACT==1) && (RD==1) && (PRE==0)) begin
        wait(dimm_time + tBURST + tCAS <= time_t);
        $display(" %t \t channel=%d, PRE bank_group=%d, bank=%d", $time, output_data[6],output_data[9:7],output_data[11:10]);
        $fwrite(file_write,"%8t \t %d\t PRE  %2d %2d\n", $time, output_data[6],output_data[9:7],output_data[11:10]);
        PRE=1; dimm_time = dimm_time + tCAS + tBURST;
      end
      
      // Pop-out after tRP
      if((ACT==1) && (RD==1) && (PRE==1)) begin
        wait(dimm_time +tRP <= time_t);
        ACT=0; RD=0; PRE=0; DONE=1;
      end
      $display(" %t \t tRCD=%0d, tBURST=%0d, tCAS=%0d, tRP=%0d \n", $time, tRCD, tBURST, tCAS, tRP);
    end

   // WRITE OPERATIONS

    if(output_data[37:36]==1) begin
      $display("---------------------------WRITE OPERATION--------------------------OPERATION=%d----------------------------", output_data[37:36]);
      
      // DRIVE ACT COMMANDS
      if(ACT==0) begin
        dimm_time = time_t;
        wait(dimm_time <= time_t);
        $display(" %t \t channel=%d, ACT0 bank_group=%d, bank=%d, row=%h", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        $fwrite(file_write,"%8t \t %d\t ACT0 %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        wait(dimm_time+2 <= time_t);
        $display(" %t \t channel=%d, ACT1 bank_group=%d, bank=%d, row=%h", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        $fwrite(file_write,"%8t \t %d\t ACT1 %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],output_data[33:18]);
        ACT = 1; dimm_time = dimm_time + 2;
      end

      // DRIVE WRITE COMMANDS
      if((ACT==1) && (WR==0)) begin
        wait(dimm_time + tRCD <= time_t);
        $display(" %t \t channel=%d, WR0 bank_group=%d, bank=%d, column=%h", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        $fwrite(file_write,"%8t \t %d\t WR0  %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        wait(dimm_time + tRCD + 2 <= time_t);
        $display(" %t \t channel=%d, WR1 bank_group=%d, bank=%d, column=%h", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        $fwrite(file_write,"%8t \t %d\t WR1  %2d %2d %h\n", $time, output_data[6],output_data[9:7],output_data[11:10],{output_data[17:12], output_data[5:2]});
        WR=1; dimm_time = dimm_time + tRCD + 2;
      end

      // DRIVE PRE COMMAND
      if((ACT==1) && (WR==1) && (PRE==0)) begin
        wait(dimm_time + tBURST + tCWL  + tWR <= time_t);
        $display(" %t \t channel=%d, PRE bank_group=%d, bank=%d", $time, output_data[6],output_data[9:7],output_data[11:10]);
        $fwrite(file_write,"%8t \t %d\t PRE  %2d %2d\n", $time, output_data[6],output_data[9:7],output_data[11:10]);
        PRE=1; dimm_time = dimm_time + tCWL + tBURST + tWR;
      end
      
      // Pop-out after tRP
      if((ACT==1) && (WR==1) && (PRE==1)) begin
        wait(dimm_time +tRP <= time_t);
        ACT=0; WR=0; PRE=0; DONE=1;
        $display("----------------------------------------POP_FRONT------------------------------------------------------------------");
       end
      $display(" %t \t tRCD=%0d, tBURST=%0d, tCWL=%0d, tRP=%0d, tWR=%0d", $time, tRCD, tBURST, tCWL, tRP, tWR);
    end
    $fclose(file_write);
  end 
end
  else begin
   $display("error :please provide the output_file using +output_file=<filename>");
  end 
end 
endtask

// pop out from local queue and push to master queue 
always@(time_t) begin
  if((full_qu == 0) && (q_time.size()!=0)) begin
    simulation_t=q_time.pop_front();              
    wait(simulation_t<= time_t);
    mem_ctrl_store();
  end
end

always@(time_t) begin
  if((q_memctrl.size()!=0)) begin
    if((time_t) % 2 == 0) toggle_out_from_memctrl_q();
  end
end

always@(time_t) begin
  if(q_memctrl.size() == 0) begin 
    empty_qu =1; 
  end
  else empty_qu =0;
  if(q_memctrl.size == 15) begin
    full_qu=1;
     $display(" memory controller queue is full");
  end
  else full_qu =0;
end

initial begin
  parsing();
end

initial begin
  time_t=0;
  #10000000 $finish;
end

endmodule