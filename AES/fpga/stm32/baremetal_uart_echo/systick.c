#include "device_driver.h"

void SysTick_Run(void)
{
  SysTick->CTRL = (0<<2)|(0<<1)|(0<<0);
  SysTick->LOAD = 0x00FFFFFF;
  SysTick->VAL = 0;
  Macro_Set_Bit(SysTick->CTRL, 0);
}
