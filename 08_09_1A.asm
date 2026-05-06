;****************************************************************************
;                                                                           *
;   Filename:		0810Nimh_3levels_v3.asm                                  *
;   Date:          	15APR2026                                               *
;   File Version:  	v3.0 (final)                                            *
;                                                                           *
;	BASIERT AUF: Microchip Reference Design 0810Nimh.asm v1.0 (Aug 2006)    *
;	Original-Autoren: Scott Dearborn, Terry Cleveland, Brian Chu            *
;                                                                           *
;	MODIFIKATION:                                                            *
;	Drei waehlbare Ladestrom-Stufen: 0,8 / 0,9 / 1,0 A                       *
;	Realisiert ueber Variation des PR2-Registers (Schaltfrequenz),          *
;	NICHT ueber Variation der Duty-Bits.                                    *
;                                                                           *
;	HINTERGRUND:                                                             *
;	Der MCP1630 ist ein Peak-Current-Mode Controller. Der OSC_IN-Pin        *
;	(vom PIC-PWM gespeist) bestimmt die Schaltfrequenz, NICHT direkt        *
;	das Tastverhaeltnis. Eine niedrigere Frequenz reduziert den             *
;	uebertragenen Strom annaehernd linear.                                  *
;                                                                           *
;	Verifizierte Messpunkte (CCPR1L=0x83, CCP1CON=0x0C konstant):            *
;	  PR2=0x03 -> 1,20 A                                                     *
;	  PR2=0x05 -> 0,89 A                                                     *
;	  PR2=0x07 -> 0,63 A                                                     *
;	-> Lineare Interpolation:                                                *
;	  PR2=0x04 -> ~1,00 A                                                    *
;	  PR2=0x06 -> ~0,76 A                                                    *
;                                                                           *
;	Original Microchip Software License Agreement gilt weiterhin.           *
;                                                                           *
;****************************************************************************

	list      p=12F683
	#include <p12F683.inc>

	errorlevel  -302

;****************************************************************************
;Configuration bits - UNVERAENDERT vom Original
	__CONFIG   0x33E4 


;****************************************************************************
; +-----------------------------------------------------------------------+
; |  >>>  HIER DEN GEWUENSCHTEN LADESTROM AUSWAEHLEN  <<<                 |
; |                                                                         |
; |  Eine Zeile aktivieren (Semikolon entfernen),                           |
; |  die anderen beiden auskommentieren.                                    |
; +-----------------------------------------------------------------------+

CHARGE_LEVEL  EQU  0    ; 0,8 A   (PR2 = 0x06)
;CHARGE_LEVEL  EQU  1    ; 0,9 A   (PR2 = 0x05)  <-- Default, verifiziert
;CHARGE_LEVEL  EQU  2    ; 1,0 A   (PR2 = 0x04) NUR MIT AKTIVER KÜHLUNG!!!


;****************************************************************************
; PWM-Konfiguration
;
; CCPR1L und CCP1CON bleiben wie im Original.
; Nur PR2 wird je nach gewuenschtem Ladestrom angepasst.
;****************************************************************************

  IF CHARGE_LEVEL == 0
PR2_VALUE     EQU  0x06           ; 0,8 A
  ENDIF
  IF CHARGE_LEVEL == 1
PR2_VALUE     EQU  0x05           ; 0,9 A (verifiziert: 0,88-0,90 A)
  ENDIF
  IF CHARGE_LEVEL == 2
PR2_VALUE     EQU  0x04           ; 1,0 A
  ENDIF


;****************************************************************************
;Constant definitions - UNVERAENDERT vom Original

;BC_STATUS bits
OVER_TEMPERATURE	EQU	0x00
OVER_VOLTAGE		EQU	0x01
PRECONDITION		EQU	0x02
TOP_OFF_CHARGE		EQU	0x03

;Battery Voltages
VBAT50H				EQU 0x02		;above 5V test
VBAT50L				EQU	0x00		;above 5V test
VBAT30H				EQU	0x01		;preconditioning threshold
VBAT30L				EQU	0x33		;preconditioning threshold
VBAT20H				EQU	0x00		;connection threshold
VBAT20L				EQU	0xCD		;connection threshold

;Battery Temperatures
TEMP55				EQU	0x3B		;55 degrees Celcius
TEMP45				EQU	0x4E		;45 degrees Celcius

;Timer
PWR_UP_DELAY		EQU	0x08		;2 seconds
CHARGE_DELAY		EQU	0x08		;2 seconds
OV_DELAY			EQU	0x28		;10 seconds
RECHARGE_DELAY		EQU	0x08		;2 seconds
AD_SETUP_DELAY		EQU	0x10		;8 uS

LOOPS_IN_MINUTE		EQU	0x39		;change with TIME_IN_LOOPS
TIME_IN_LOOPS		EQU	0x04		;change with LOOPS_IN_MINUTE

;GPIO
LED					EQU	0x04
CHARGE_CURRENT		EQU	0x05 

;****************************************************************************
;Variable definitions - UNVERAENDERT

INT_VAR				UDATA_SHR	0x70   
BC_STATUS			RES	1
VBAT_AVEH			RES	1
VBAT_AVEL			RES	1
VBAT_REFH			RES	1
VBAT_REFL			RES	1
TEMP_AVE			RES	1
TEMP_REF			RES	1
DELAY_COUNT			RES	1
LOOP_COUNT			RES	1
MINUTE_COUNT		RES	1
TIMEOUT				RES	1
PERSISTANCE_UP		RES	1
PERSISTANCE_DOWN	RES	1
TOP_OFF_COUNT		RES	1
OV_COUNT			RES	1

;****************************************************************************
RESET_VECTOR	CODE	0x000		; processor reset vector
		goto    MAIN              	; go to beginning of program


INT_VECTOR	CODE	0x004			; interrupt vector location
		bsf		CCPR1L,7
		bsf		BC_STATUS,OVER_VOLTAGE
		movf	CMCON0,F
		clrf	PIR1

		retfie                    ; return from interrupt


MAIN
;****************************************************************************
;Initialize oscillator
		movlw	0x71				;set internal oscillator to 8MHz
		bsf		STATUS,RP0
		movwf	OSCCON
CLOCK_STABLE?
		btfss	OSCCON,HTS			;frequency stable?
		goto	CLOCK_STABLE?		;no, wait

;****************************************************************************
;Initialize ports
		movlw	0x2B				 
		movwf	TRISIO				;set CCP1, GP5 to output
		movlw	0x04				;set CCP1 to a logic HIGH
		bcf		STATUS,RP0
		movwf	GPIO

;****************************************************************************
;Initialize ADC
		movlw	0x85
		movwf	ADCON0
		movlw	0x53
		bsf		STATUS,RP0
		movwf	ANSEL

;****************************************************************************
;Initialize comparator
		movlw	0x04
		bcf		STATUS,RP0
		movwf	CMCON0
		movlw	0xAD
		bsf		STATUS,RP0
		movwf	VRCON

;****************************************************************************
;Initialize PWM     <<< MODIFIZIERT: nur PR2 aenderbar >>>
		movlw	PR2_VALUE			; aus Konstante oben
		movwf	PR2
		movlw	0x82				; UNVERAENDERT vom Original
		bcf		STATUS,RP0
		movwf	CCPR1L
		movlw	0x0C				; UNVERAENDERT vom Original
		movwf	CCP1CON

;****************************************************************************
;Initialize Timers
		clrf	TMR1H
		clrf	TMR1L
		bcf		PIR1,TMR1IF
		movlw	0x31
		movwf	T1CON

;****************************************************************************
;Initialize Variables
		movlw	0x70
		movwf	FSR
NEXT	clrf	INDF
		incf	FSR,F
		btfss	FSR,7
		goto	NEXT

;****************************************************************************
;POWER_UP_DELAY
		clrf	OV_COUNT
		movlw	PWR_UP_DELAY
		movwf	DELAY_COUNT

DELAY_LOOP
		btfss	PIR1,TMR1IF
		goto	$-1
		bcf		PIR1,TMR1IF
		decfsz	DELAY_COUNT,F
		goto	DELAY_LOOP

;Clear Interrupt
		movf	CMCON0,F
		clrf	PIR1
		bsf		STATUS,RP0
		clrf	PIE1
		bcf		STATUS,RP0
		clrf	INTCON
		clrf	BC_STATUS


;****************************************************************************
;Battery Connected ?
WAIT_FOR_BATTERY_CONNECTED
		bsf		STATUS,RP0
		bsf		TRISIO,CHARGE_CURRENT
		bcf		STATUS,RP0
		bcf		GPIO,LED
		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO	
		goto	$-1
		bsf		STATUS,RP0
		movf	ADRESL,W
		movwf	VBAT_REFL
		movwf	VBAT_AVEL
		bcf		STATUS,RP0
		movf	ADRESH,W
		movwf	VBAT_REFH
		movwf	VBAT_AVEH
		movf	VBAT_REFH,F
		btfss	STATUS,Z
		goto	CHARGE_CYCLE_START
		movf	VBAT_REFL,W
		sublw	VBAT20L				;precondition to detect battery at 2V
		btfsc	STATUS,C
		goto	WAIT_FOR_BATTERY_CONNECTED

;****************************************************************************
;CHARGE_CYCLE_START
CHARGE_CYCLE_START
		bcf		ADCON0,CHS0
		bcf		ADCON0,ADFM

		movlw	CHARGE_DELAY
		movwf	DELAY_COUNT
CHARGE_START_DELAY
		btfss	PIR1,TMR1IF
		goto	$-1
		bcf		PIR1,TMR1IF
		decfsz	DELAY_COUNT,F
		goto	CHARGE_START_DELAY

		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO	
		goto	$-1
		movf	ADRESH,W
		movwf	TEMP_REF
		movwf	TEMP_AVE
		bsf		ADCON0,CHS0
		bsf		ADCON0,ADFM
		movlw	TIME_IN_LOOPS
		movwf	LOOP_COUNT
		movlw	LOOPS_IN_MINUTE
		movwf	MINUTE_COUNT
		clrf	TOP_OFF_COUNT
		bcf		CCPR1L,7
		clrf	PERSISTANCE_UP
		clrf	PERSISTANCE_DOWN
		bsf		T2CON,TMR2ON
		bsf		GPIO,LED
		bsf		BC_STATUS,PRECONDITION

INITIALIZE_OV_INTERRUPT
		movf	CMCON0,F
		clrf	PIR1
		bsf		STATUS,RP0
		movlw	0x08
		movwf	PIE1
		bcf		STATUS,RP0
		movlw	0xC0
		movwf	INTCON

ACQUISITION_LOOP
		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO
		goto	$-1
		bcf		ADCON0,CHS0
		nop
		nop
		nop
		bsf		STATUS,RP0
		movf	ADRESL,W
		addwf	VBAT_AVEL,F
		bcf		STATUS,RP0
		btfsc	STATUS,C
		incf	VBAT_AVEH
		movf	ADRESH,W
		addwf	VBAT_AVEH,F
		rrf		VBAT_AVEH,F		
		rrf		VBAT_AVEL,F
		bcf		ADCON0,ADFM
		nop
		nop
		nop
		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO
		goto	$-1
		bsf		ADCON0,CHS0							;ready to read temperature
		nop
		movf	ADRESH,W
		addwf	TEMP_AVE,F
		rrf		TEMP_AVE,F		
		bsf		ADCON0,ADFM
		btfsc	BC_STATUS,OVER_VOLTAGE
		goto	BATTERY_REMOVED						;battery disconnected
		btfss	PIR1,TMR1IF
		goto	ACQUISITION_LOOP

		bcf		PIR1,TMR1IF
		decfsz	LOOP_COUNT,F
		goto	ACQUISITION_LOOP
		movlw	TIME_IN_LOOPS
		movwf	LOOP_COUNT
		decfsz	MINUTE_COUNT,F
		goto	CHECK_VOLTAGE
		movlw	LOOPS_IN_MINUTE
		movwf	MINUTE_COUNT
		clrf	OV_COUNT

CHECK_TEMPERATURE
		btfsc	BC_STATUS,TOP_OFF_CHARGE
		incf	TOP_OFF_COUNT,F
		movf	TEMP_AVE,W
		sublw	TEMP55
		btfsc	STATUS,C
		goto	TEMPERATURE_FAULT
		
  		movlw 	0x04
 		addwf 	TEMP_AVE,W
		subwf 	TEMP_REF,W
		btfss 	STATUS,C
		goto	UPDATE_TEMP_REF
		bcf		GPIO,CHARGE_CURRENT
		bsf  	BC_STATUS,TOP_OFF_CHARGE
 		goto 	ACQUISITION_LOOP
    
UPDATE_TEMP_REF
		movf	TEMP_AVE,W
		movwf	TEMP_REF
	
CHECK_VOLTAGE
		btfsc	BC_STATUS,TOP_OFF_CHARGE
		goto	TIMED_TOP_OFF_CHARGE
		btfss	BC_STATUS,PRECONDITION
		goto	CHECK_VOLTAGE_PLATEAU

;Precondition
		movf	VBAT_AVEH,W
		sublw	VBAT30H
		btfss	STATUS,C
		goto	END_PRECONDITION
		btfss	STATUS,Z
		goto	STAY_IN_PRECONDITION
		movf	VBAT_AVEL,W
		sublw	VBAT30L
		btfsc	STATUS,C
		goto	STAY_IN_PRECONDITION

END_PRECONDITION
		incf	PERSISTANCE_UP,F
		btfss	PERSISTANCE_UP,2
		goto	ACQUISITION_LOOP
		clrf	PERSISTANCE_UP
		clrf	PERSISTANCE_DOWN
		movf	VBAT_AVEH,W
		movwf	VBAT_REFH
		movf	VBAT_AVEL,W
		movwf	VBAT_REFL
		bsf		STATUS,RP0
		bcf		TRISIO,CHARGE_CURRENT
		bcf		STATUS,RP0
		bsf		GPIO,CHARGE_CURRENT
		bcf		BC_STATUS,PRECONDITION
		goto	ACQUISITION_LOOP

STAY_IN_PRECONDITION
		clrf	PERSISTANCE_UP
		goto	ACQUISITION_LOOP

CHECK_VOLTAGE_PLATEAU
		movf 	VBAT_AVEH,W
  		subwf 	VBAT_REFH,W
  		btfsc 	STATUS,Z
  		goto 	HIGH_BYTE_EQUAL
  		btfsc 	STATUS,C
  		goto 	VOLTAGE_DECREASING

VOLTAGE_INCREASING
 		clrf 	PERSISTANCE_DOWN
		incf	PERSISTANCE_UP,F
		btfss	PERSISTANCE_UP,3
		goto	ACQUISITION_LOOP
  		incf 	VBAT_REFL,F
		btfsc	STATUS,Z
		incf	VBAT_REFH,F
		clrf	PERSISTANCE_UP
		goto	ACQUISITION_LOOP

HIGH_BYTE_EQUAL
		movf 	VBAT_AVEL,W
  		subwf 	VBAT_REFL,W
  		btfsc 	STATUS,Z
  		goto 	LOW_BYTE_EQUAL
  		btfsc 	STATUS,C
  		goto 	VOLTAGE_DECREASING
 		goto	VOLTAGE_INCREASING

LOW_BYTE_EQUAL
 		clrf 	PERSISTANCE_DOWN
		clrf 	PERSISTANCE_UP
  		goto 	ACQUISITION_LOOP

VOLTAGE_DECREASING
		clrf	PERSISTANCE_UP
  		incf 	PERSISTANCE_DOWN,F
  		btfss 	PERSISTANCE_DOWN,4
		goto 	ACQUISITION_LOOP
		bcf		GPIO,CHARGE_CURRENT
  		bsf  	BC_STATUS,TOP_OFF_CHARGE
  		goto 	ACQUISITION_LOOP

TIMED_TOP_OFF_CHARGE
  		movf 	VBAT_AVEH,W
		movwf	VBAT_REFH
		movf	VBAT_AVEL,W
  		movwf 	VBAT_REFL
		btfsc	GPIO,LED
		goto	TURN_OFF_LED1
		bsf		GPIO,LED
		goto	CHECK_TOP_OFF_TIME
TURN_OFF_LED1
		bcf		GPIO,LED		
CHECK_TOP_OFF_TIME
		clrf	PERSISTANCE_UP
 		clrf 	PERSISTANCE_DOWN
		btfss	TOP_OFF_COUNT,6
		goto	ACQUISITION_LOOP

		clrf	TOP_OFF_COUNT
		bsf		CCPR1L,7
		bcf		GPIO,LED

CHARGE_COMPLETE_LOOP
		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO	
		goto	$-1
		bsf		STATUS,RP0
		movf	ADRESL,W
		addwf	VBAT_AVEL,F
		bcf		STATUS,RP0
		btfsc	STATUS,C
		incf	VBAT_AVEH
		movf	ADRESH,W
		addwf	VBAT_AVEH,F
		rrf		VBAT_AVEH,F		
		rrf		VBAT_AVEL,F
		btfss	PIR1,TMR1IF
		goto	CHARGE_COMPLETE_LOOP
		bcf		PIR1,TMR1IF
		movf	VBAT_AVEH,F
		btfss	STATUS,Z
		goto	CHARGE_COMPLETE_LOOP
		movf	VBAT_REFL,W
		sublw	VBAT20L				;precondition to detect battery at 2V
		btfss	STATUS,C
		goto	CHARGE_COMPLETE_LOOP
		movlw	RECHARGE_DELAY
		movwf	DELAY_COUNT
		goto	DELAY_LOOP

;Battery removed during charge - over voltage
BATTERY_REMOVED
		bcf		GPIO,LED
		clrf	BC_STATUS
		incf	OV_COUNT,F
		btfsc	OV_COUNT,2
		goto	FAULT_LOOP
		movlw	OV_DELAY
		movwf	DELAY_COUNT
		goto	DELAY_LOOP

TEMPERATURE_FAULT
		bsf		CCPR1L,7
		bcf		ADCON0,CHS0
		bcf		ADCON0,ADFM
		movlw	AD_SETUP_DELAY
		movwf	DELAY_COUNT
		decfsz	DELAY_COUNT,F
		goto	$-1		
		clrf	PERSISTANCE_UP
		clrf	PERSISTANCE_DOWN
TEMPERATURE_LOOP
		btfsc	GPIO,LED
		goto	TURN_OFF_LED2
		bsf		GPIO,LED
		goto	CHECK_IF_TEMPERATURE_OKAY
TURN_OFF_LED2
		bcf		GPIO,LED
CHECK_IF_TEMPERATURE_OKAY
		bsf		ADCON0,GO
		nop
		btfsc	ADCON0,GO
		goto	$-1
		movf	ADRESH,W
		addwf	TEMP_AVE,F
		rrf		TEMP_AVE,F		
		btfss	PIR1,TMR1IF
		goto	CHECK_IF_TEMPERATURE_OKAY
		bcf		PIR1,TMR1IF
		movf	TEMP_AVE,W
		sublw	TEMP45
		btfsc	STATUS,C
		goto	TEMPERATURE_LOOP
		bsf		ADCON0,CHS0
		bsf		ADCON0,ADFM
		movlw	AD_SETUP_DELAY
		movwf	DELAY_COUNT
		decfsz	DELAY_COUNT,F
		goto	$-1
		btfss	BC_STATUS,TOP_OFF_CHARGE
		goto	RETURN_IN_PRECONDITION		
		bcf		CCPR1L,7
		bsf		GPIO,LED
		goto	ACQUISITION_LOOP

RETURN_IN_PRECONDITION
		bsf		STATUS,RP0
		bsf		TRISIO,CHARGE_CURRENT
		bcf		STATUS,RP0
		bsf		BC_STATUS,PRECONDITION		
		btfss	PIR1,TMR1IF
		goto	$-1
		bcf		PIR1,TMR1IF
		bcf		CCPR1L,7
		bsf		GPIO,LED
		goto	ACQUISITION_LOOP

FAULT_LOOP
		btfsc	GPIO,LED
		goto	TURN_OFF_LED3
		bsf		GPIO,LED
		goto	STAY_IN_FAULT_FOREVER
TURN_OFF_LED3
		bcf		GPIO,LED
STAY_IN_FAULT_FOREVER
		btfss	PIR1,TMR1IF
		goto	$-1
		bcf		PIR1,TMR1IF
		goto	FAULT_LOOP
		
; initialize eeprom locations

EE		CODE	0x2100
		DE	0x00, 0x00, 0x00, 0x00


		END                       ; directive 'end of program