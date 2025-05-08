--RS232TX
Library IEEE;
Use IEEE.std_logic_1164.all;
Use IEEE.std_logic_unsigned.all;
-- ----------------------------------------------------
Entity RS232_T4 is
	generic
	(
		TXRD_buff : natural--定義buffer 大小
	);
	Port(Clk,Reset:in std_logic;--clk:50MHz
		 DL:in std_logic_vector(1 downto 0);	 --00:5,01:6,10:7,11:8 Bit
		 ParityN:in std_logic_vector(2 downto 0);--0xx:None,100:Even,101:Odd,110:Space,111:Mark
		 StopN:in std_logic_vector(1 downto 0);	 --0x:1Bit,10:2Bit,11:1.5Bit
		 F_Set:in std_logic_vector(3 downto 0);	--BaudRate:000:1200,001:2400,010:4800,011:9600,100:19200,101:38400,110:57600,111:115200
		 Status_s:out std_logic_vector(1 downto 0);
		 TX_W:in std_logic;
		 TXData:in std_logic_vector(7 downto 0);
		 TX:out std_logic);
End RS232_T4;
-- -----------------------------------------------------
Architecture RS232_T4_Arch of RS232_T4 is
Signal StopNn:std_logic_vector(2 downto 0);
Signal Tx_B_Empty,Tx_B_Clr,TxO_W:std_logic;
-------------
Signal BaudRateset:std_logic_vector(5 downto 0);	--BaudRate
Signal Tx_f,T_Half_f,TX_P_NEOSM,TxB_Load:std_logic;
Signal TXDs_Bf,TXD2_Bf:std_logic_vector(7 downto 0);
Signal Tsend_DLN,DLN:std_logic_vector(3 downto 0);
Signal Tx_s:std_logic_vector(2 downto 0);
Signal TX_BaudRate:integer range 0 to 41667;
Signal BaudRate1234:std_logic_vector(1 downto 0);
type buffer_data_T is array(0 to TXRD_buff) of std_logic_vector(7 downto 0);--send緩衝器加大版256byte
signal TX_B_data:buffer_data_T;							--send緩衝器
Signal TX_B_P0,TX_B_P1:integer range 0 to TXRD_buff;	--緩衝器資料取出、加入指標

Signal TX_BBN:integer range 0 to (TXRD_buff+1);--1023;--緩衝器資料量
-- --------------------------
Begin
-----------------------------
Status_s<=TxB_Load & TxO_W;
-----------------------------
TxP_L:Process(Clk,Reset)
Begin
If reset='0' Then
	TX_B_P0<=0;	
	Tx_B_Empty<='0';	
	TxO_W<='0';
	TxB_Load<='0';
	TX_B_P1<=0;
	TX_BBN<=0;
elsif TX_BBN>512 and TxB_Load='0' then
	TxB_Load<='1';
	TxO_W<='1';
elsif Tx_B_Clr='1' Then
	Tx_B_Empty<='0';
Elsif Clk'event and Clk='1' Then
	if Tx_s=0 and TX_BBN>0 and TX_BBN<(TXRD_buff+2) and Tx_B_Empty='0' then
		TXD2_Bf<=TX_B_data(TX_B_P0);
		TX_B_P0<=TX_B_P0+1;	
		Tx_B_Empty<='1';	--Tx_B_Empty='1'表示已有資料寫入(尚未傳出)
		TX_BBN<=TX_BBN-1;
	elsif TX_W='1' and TxB_Load='0' then
		TX_B_data(TX_B_P1)<=TXData;
		TX_B_P1<=TX_B_P1+1;
		TX_BBN<=TX_BBN+1;
		TxB_Load<='1';
	elsif TxB_Load='1' then
		if TX_W='0' then
			TxB_Load<='0';
		end if;
	elsif TX_BBN<513 then
		TxB_Load<='0';
		TxO_W<='0';
	end if;
End If;
End Process TxP_L;

---------------------------------------------------------------
TxP:Process(Tx_f,Reset)
Begin
If Reset='0' Then
	Tx_s<="000";
	TX<='1';
	Tx_B_Clr<='0';
Elsif Tx_f'event and Tx_f='1' Then
	If Tx_s=0 and Tx_B_Empty='1' Then--start bit
		TXDs_Bf<=TXD2_Bf;		
		TX<='0';					--start bit
		Tsend_DLN<="0000";
		TX_P_NEOSM<=ParityN(0);		--Even,Odd,Space or Mark
		Tx_B_Clr<='1';
		T_Half_f<='0';
		Tx_s<="001";
	Elsif Tx_s/=0 Then
		Tx_B_Clr<='0';
		T_Half_f<=Not T_Half_f;
		Case Tx_s is
			When "001" =>
				If T_Half_f='1' Then
					if Tsend_DLN=DLN Then
						If ParityN(2)='0' Then 	--None Parity Bit
							Tx_s<=StopNn;
							TX<='1';			--Stop Bit
						Else
							TX<=TX_P_NEOSM;		--Parity Bit
							Tx_s<="010";
						End If;
					Else
						If ParityN(1)='0' Then
							TX_P_NEOSM<=TX_P_NEOSM Xor TXDs_Bf(0);--Even or Odd
						End If;
						TX<=TXDs_Bf(0);			--Send Data:Bit 0..7
						TXDs_Bf<=TXDs_Bf(0) & TXDs_Bf(7 Downto 1);
						Tsend_DLN<=Tsend_DLN+1;
					End If;
				End If;
			When "011" =>
				Tx_s<=StopNn;
				TX<='1';	--Stop Bit
			When oThers=>
				Tx_s<=Tx_s+1;
		End Case;
	End If;
End If;
End Process TxP;
--------------------------
TxBaudP:process(Clk,Reset)
VARIABLE f_Div:integer range 0 to 41667;
Begin
	If Reset='0' Then
		f_Div:=0;Tx_f<='0';BaudRate1234<="00";
	Elsif clk'event and clk='1' Then
		If f_Div=TX_BaudRate Then
			f_Div:=0;
			Tx_f<=Not Tx_f;
			BaudRate1234<=BaudRate1234+1;
		Else
			f_Div:=f_Div+1;
		End If;
	End If;
End Process TxBaudP;
------------------------------------------
BaudRateset<=F_Set & BaudRate1234;
With BaudRateset Select
  TX_BaudRate<=	--Baud Rate Set 依Clk=50MHz設定:50000000/(41666*4)=300
  		41667 When "000000",--300
		41667 When "000001",--300
		41667 When "000010",--300
		41666 When "000011",--300
        20833 When "000100",--600
        20834 When "000101",--600
        20833 When "000110",--600
        20833 When "000111",--600
		10416 When "001000",--1200
        10417 When "001001",--1200
        10417 When "001010",--1200
        10417 When "001011",--1200
        5208  When "001100",--2400
        5209  When "001101",--2400
        5208  When "001110",--2400
        5208  When "001111",--2400
        2604  When "010000",--4800
        2605  When "010001",--4800
        2604  When "010010",--4800
        2604  When "010011",--4800
        1302  When "010100",--9600
        1302  When "010101",--9600
        1302  When "010110",--9600
        1302  When "010111",--9600
        651   When "011000",--19200
        651   When "011001",--19200
        651   When "011010",--19200
        651   When "011011",--19200
        434   When "011100",--28800
        434   When "011101",--28800
        434   When "011110",--28800
        434   When "011111",--28800
        325   When "100000",--38400
        326   When "100001",--38400
        326   When "100010",--38400
        325   When "100011",--38400
        217   When "100100",--57600
        217   When "100101",--57600
        217   When "100110",--57600
        217   When "100111",--57600
        162   When "101000",--76800
        163   When "101001",--76800
        163   When "101010",--76800
        163   When "101011",--76800
        108   When "101100",--115200
        109   When "101101",--115200
        108   When "101110",--115200
        108   When "101111",--115200
        54    When "110000",--230400
        55    When "110001",--230400
        54    When "110010",--230400
        54    When "110011",--230400
        27    When "110100",--460800
        27    When "110101",--460800
        28    When "110110",--460800
        27    When "110111",--460800
        21    When "111000",--576000
        22    When "111001",--576000
        22    When "111010",--576000
        22    When "111011",--576000
        13    When "111100",--921600
        14    When "111101",--921600
        14    When "111110",--921600
        13    When "111111",--921600
        0 	  When oThers;
-------------------------------
--		50000000 50000000		0.00000002	0.000000005			
--0000--300	     0.003333333	166666.6667	41666.66667	41666.7	166667	41667+41667+41667+41666
--0001--600	     0.001666667	83333.33333	20833.33333	20833.3	83333	20833+20834+20833+20833
--0010--1200	 0.000833333	41666.66667	10416.66667	10416.7	41667	10416+10417+10417+10417
--0011--2400	 0.000416667	20833.33333	5208.333333	5208.3	20833	5208+5209+5208+5208
--0100--4800	 0.000208333	10416.66667	2604.166667	2604.2	10417	2604+2605+2604+2604
--0101--9600	 0.000104167	5208.333333	1302.083333	1302.1	5208	1302+1302+1302+1302
--0110--19200	 5.20833E-05	2604.166667	651.0416667	651		2604	651+651+651+651
--0111--28800	 3.47222E-05	1736.111111	434.0277778	434		1736	434+434+434+434
--1000--38400	 2.60417E-05	1302.083333	325.5208333	325.5	1302	325+326+326+325
--1001--57600	 1.73611E-05	868.0555556	217.0138889	217		868		217+217+217+217
--1010--76800	 1.30208E-05	651.0416667	162.7604167	162.8	651		162+163+163+163
--1011--115200   8.68056E-06	434.0277778	108.5069444	108.5	433		108+109+108+108
--1100--230400   4.34028E-06	217.0138889	54.25347222	54.3	217		54+55+54+54
--1101--460800   2.17014E-06	108.5069444	27.12673611	27.1	109		27+27+28+27
--1110--576000   1.73611E-06	86.80555556	21.70138889	21.7	87		21+22+22+22
--1111--921600   1.08507E-06	54.25347222	13.56336806	13.6	54		13+14+14+13
----------------------------------
With DL Select				--Data Length 
  DLN<= "0101" When "00",   --5bit 
        "0110" When "01",	--6bit
        "0111" When "10",	--7bit
        "1000" When "11",	--8bit
        "0000" When oThers;
----------------------------------        
With StopN Select			--Stop Bit
  StopNn<="101" When "10",	--2Bit
          "110" When "11",	--1.5Bit
          "111" When oThers;--1Bit
---------------------------------------------------------------
End RS232_T4_Arch;
