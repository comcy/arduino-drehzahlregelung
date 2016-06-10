#include <Arduino.h>
#include <stdlib.h>


/* Definitionen */
#define PWM_OUT  5
#define DIR_OUT  4
#define SPUR_A  9
#define SPUR_B  2

#define LINKS  true
#define RECHTS false

#define MAX_INT         INT16_MAX
#define MAX_LONG        INT32_MAX
#define MAX_I_TERM      (MAX_LONG / 2)


/* Globale Variablen */
uint16_t pwm;
uint16_t flags;
int16_t impuls_cnt;
int16_t positionIst;
int16_t positionSoll;
int16_t fImpulsIst;
int16_t fImpulsSoll;
bool b_position;
bool b_impuls;
bool b_position_flag;

int16_t task_var;


/* Funktionsprototypen */
uint32_t pwm_callback(uint32_t current_time);
void set_rpm(int16_t rpm);
uint32_t getRpm_callback(uint32_t currentTime);
void spur_interrupt(void);
uint32_t position_callback(uint32_t currentTime);
void constant_drive(uint8_t swi);



/* Setup Funktion */
void setup(void)
{
    /* Variablen initalisieren */
    pwm = 0;
    flags = 0;
    impuls_cnt = 0;
    positionIst = 0;
    positionSoll = 0;
    fImpulsIst = 0;
    fImpulsSoll = 0;
    b_position = false;
    b_impuls = false;
    b_position_flag = true;
    
    
    /* Peripherie Konfigurieren */
    pinMode(PWM_OUT,OUTPUT);
    pinMode(DIR_OUT,OUTPUT);
    pinMode(SPUR_A, INPUT);
    pinMode(SPUR_B, INPUT);
    Serial.begin(9600);
    
    /* Tasks erzeugen */
    createTask(position_callback, 100, TASK_ENABLE, &task_var);
    
    /* Interrupts einstellen */
    attachCoreTimerService(pwm_callback);
    attachCoreTimerService(getRpm_callback);
    attachInterrupt(1, spur_interrupt, RISING);
    
    delay(1000);
    Serial.println("press m for menue");
}

/* Main Funktion */
void loop(void)
{
    uint8_t u8_recv, temp;
    uint8_t i;
    
    if(Serial.available())
        u8_recv = Serial.read();
    
    
    switch(u8_recv)
    {
        case 'm':   Serial.println("Menu:");
                    Serial.println("External Drive:          1");
                    Serial.println("Four Positions:          2");
                    Serial.println("Constant drive (slow):   3");
                    Serial.println("Constant drive (medium): 4");
                    Serial.println("Constant drive (fast):   5");
        break;
        
        case '1':   Serial.println("External Drive");
                    b_position = false; /* Positionsregelung abschalten */
                    b_impuls = false;   /* Drehzahlregelung abschalten */
                    
                    do
                    {
                        Serial.print(((float)fImpulsIst)*60.0 / 5400.0);
                        Serial.println(" rpm");
                        delay(500);
                    }while(!Serial.available());
                    temp = Serial.read();   /* Serial Buffer leeren */
                    
        break;
        
        case '2':   Serial.println("Four Positions");
                    positionIst = 0;
                    positionSoll = 1350;
                    b_position = true;  /* Positionsregelung aktivieren */
                    b_impuls = true;    /* Drehzahlregelung aktivieren */
                    delay(5000);
                    
                    for(i=0; i<3; i++)
                    {
                        positionSoll += 1350;   /* Erhöung um 90 Grad */                        
                        delay(5000);
                        Serial.print("positionSoll: ");
                        Serial.print(positionSoll);
                        Serial.print("   positionIst: ");
                        Serial.println(positionIst);
                        
                    }
                    
        break;
        
        case '3':   Serial.println("Constant Drive (slow)");
                    constant_drive(0);
                    
        break;
        
        case '4':   Serial.println("Constant Drive (medium)");
                    constant_drive(1);
        break;
        
        case '5':   Serial.println("Constant Drive (fast)");
                    constant_drive(2);
                    
        break;
                 
        default:    
        break;
        
    }
    
   
}


/* Funktion um das PWM-Signal zu generieren */
/* Diese Funktion wird als CoreTimer Callback Funktion verwendet */
uint32_t pwm_callback(uint32_t current_time)
{
    static uint16_t cnt = 0;
    uint32_t u32_return;
    
    if( cnt >= pwm )
    {
        digitalWrite(PWM_OUT, LOW);
        flags |= (1<<0);
    }
    else
    {
        digitalWrite(PWM_OUT, HIGH);
        flags |= (1<<1);
    }
    
    cnt ++;
    cnt &= 0x07ff;
    
    u32_return = current_time + 200;
    
    return u32_return;
}


/* Funktion um die Drehzahl des Motors einzustellen */
void set_rpm(int16_t rpm)
{
    uint16_t u16_temp;
    
    pwm = abs(rpm) & 0x07ff;
    
    if(rpm >= 0)
        digitalWrite(DIR_OUT,RECHTS);
    else
        digitalWrite(DIR_OUT, LINKS);
}

/* Funktion um die Frequenz der Impulsgeber zu ermitteln */
uint32_t getRpm_callback(uint32_t currentTime)
{
    int16_t i16_i;
    static int16_t i16_temp = 0;
    
    /* Messen der Frequenz der Impulse von Spur B */
    /* Es wird die Anzahl der Impuls pro 0,01s gezaehlt */
    /* Dies wird um 100 Multipliziert um die Frequenz in Hz zu erhalten */
    fImpulsIst = impuls_cnt * 100; /* In Hz */
    impuls_cnt = 0;
    
    if(b_impuls)
    {
        /* Einfache Regelung der Drehzahl */
        /* Ist der Wert der soll Frequenz zu klein wird die Pulsbreite erhöht */
        /* Ist der Wert zu gross wird die Pulsbreite verringert */
        if(fImpulsIst < fImpulsSoll)
            i16_temp += 10;
        
        if(fImpulsIst > fImpulsSoll)
            i16_temp -= 10;
        
        /* Überprüfen auf Über oder Unterlauf der Variable */
        i16_i = 0x07ff;
        if( i16_temp > i16_i )
            i16_temp = i16_i;
        else if( i16_temp < -i16_i )
            i16_temp = -i16_i;
        
        /* Drehzahl setzten */
        set_rpm(i16_temp); 
    }
    
    return (currentTime + 400000);
    
}
    
/* Funktion die bei Impuls-Interrupt aufgerufen wird */
void spur_interrupt(void)
{
    /* Bestimmen der Drehrichtung, Anazhl der Impulse und die Absolute Positions */
    if( digitalRead(SPUR_A) )
    {
        impuls_cnt ++;
        positionIst ++;     /* Absolute Position erhöhen */
    }
    else
    {
        impuls_cnt --;
        positionIst --;     /* Absolute Position erniedirigen */
    }
}

/* Funktion um die Stellung des Motors zu regeln */
/* Diese wird als Callback-Funktion in einem Coretimer verwendet */
void position_callback(int a, void * b)
{
    int16_t i16_posDiff;
    if(b_position)
    {
        
        i16_posDiff = positionSoll - positionIst;
        
        if( (i16_posDiff < 5) && (i16_posDiff > -5) )
            fImpulsSoll = 0;
        else if( (i16_posDiff < 1400) && (i16_posDiff > -1400) )
            fImpulsSoll = 11 * i16_posDiff / 7;
        else if( i16_posDiff >= 1400 )
            fImpulsSoll = 2200;
        else
            fImpulsSoll = -2200;
    }
}

/* Funktion um eine Konstante Drehzahl einzustellen */
/* Der Funktion muss ein Wert zwischen 0 und 2 übergeben werden */
/* Dabei steht 0 für slow, 1 für medium und 2 für fast */
/* Ist der Übergabeparameter größer als 2 wird die Drehzahl auf 0 gestellt */ 
void constant_drive(uint8_t swi)
{
    uint8_t temp;
    if(swi < 3)
    {
        fImpulsSoll = 1000 + swi * 500;
        b_position = false; /* Positionsregelung abschalten */
        b_impuls = true;    /* Drehzahlregelung anschalten */
        do
        {
            Serial.print("fImpulsSoll ");
            Serial.println(fImpulsSoll);
            Serial.print("fImpulsIst ");
            Serial.println(fImpulsIst);
            delay(500);
        }while(!Serial.available());    /* So lange widerholen bis Benutzer eine Eingabe tätigt */
        fImpulsSoll = 0;
        temp = Serial.read();
    }
    else
        fImpulsSoll = 0;
        
    delay(3000);    /* Warten bis auf 0 Hz geregelt wurde */
}
