function bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] gen_unified_table();
    static bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] table_old = {CRC_WIDTH{{(DWIDTH+CRC_WIDTH){1'b0}}}};
    static bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table = {CRC_WIDTH{{(DWIDTH+CRC_WIDTH){1'b0}}}};
    for (int i = 0; i < CRC_WIDTH; i++)
        table_old[i][i] = 1'b1;
    for (int i = 0; i < DWIDTH; i++) begin
        /* - crc_out[0] = crc_in[CRC_WIDTH-1] ^ din[DWIDTH-1-i]; */
        unified_table[0] = table_old[CRC_WIDTH-1];
        unified_table[0][CRC_WIDTH+DWIDTH-1-i] = ~unified_table[0][CRC_WIDTH+DWIDTH-1-i];
        /////////////////////////////////////////////////////////////
        for (int j = 1; j < CRC_WIDTH; j++) begin
            if (CRC_POLY[j])
                unified_table[j] = table_old[j-1] ^ unified_table[0];
            else
                unified_table[j] = table_old[j-1];
        end
        table_old = unified_table;
    end    
    return unified_table;
endfunction

function bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] gen_crc_table(
    input bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table
);
    static bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] crc_table;
    for (int i = 0; i < CRC_WIDTH; i++) begin
        for (int j = 0; j < CRC_WIDTH; j++)
            crc_table[i][j] = unified_table[i][j];
    end
    return crc_table;   
endfunction

function bit [CRC_WIDTH-1:0][DWIDTH-1:0] gen_data_table(
    input bit [CRC_WIDTH-1:0][DWIDTH+CRC_WIDTH-1:0] unified_table
);
    static bit [CRC_WIDTH-1:0][DWIDTH-1:0] data_table;
    for (int i = 0; i < CRC_WIDTH; i++) begin
        for (int j = 0; j < DWIDTH; j++)
            data_table[i][j] = unified_table[i][j+CRC_WIDTH];
    end
    return data_table;   
endfunction

function int get_div_per_lvl();
    int divider_per_lvl;
    if (PIPE_LVL <= 1)
        divider_per_lvl = DWIDTH;
    else begin
        for (int j = 0; j < 100; j++) begin
            if (j**PIPE_LVL >= DWIDTH) begin
                divider_per_lvl = j;
                break;
            end
        end
    end
    return divider_per_lvl;
endfunction

function bit [PIPE_LVL:0][31:0] get_n_terms(
    input int divider_per_lvl
);
    static bit [PIPE_LVL:0][31:0] n_terms;
    n_terms[0] = DWIDTH;
    for (int i = 1; i <= PIPE_LVL; i++) begin
        n_terms[i] = (n_terms[i-1]-1)/divider_per_lvl+1;
    end
    return n_terms;
endfunction

function bit [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] get_revert_table();
    static bit [CRC_WIDTH-1:0][CRC_WIDTH-1:0] table_old;
    static bit [$clog2(DWIDTH/8)-1:0][CRC_WIDTH-1:0][CRC_WIDTH-1:0] revert_table = {$clog2(DWIDTH/8){{CRC_WIDTH{{CRC_WIDTH{1'b0}}}}}};
    for (int i = 0; i < $clog2(DWIDTH/8); i++) begin
        table_old = {CRC_WIDTH{{CRC_WIDTH{1'b0}}}};
        for (int j = 0; j < CRC_WIDTH; j++) begin
            table_old[j][j] = 1'b1;
        end
        for (int j = 0; j < DWIDTH/(2**(i+1)); j++) begin
            revert_table[i][CRC_WIDTH-1] = table_old[0];
            for (int k = 0; k < CRC_WIDTH-1; k++) begin
                if (CRC_POLY[k+1])
                    revert_table[i][k] = table_old[k+1] ^ table_old[0];
                else
                    revert_table[i][k] = table_old[k+1];
            end
            table_old = revert_table[i];
        end 
    end
    return revert_table;
endfunction