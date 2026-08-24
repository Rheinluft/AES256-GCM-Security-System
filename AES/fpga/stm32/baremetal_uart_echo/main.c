#include "device_driver.h"
#include <stdio.h>

static void Sys_Init(int baud)
{
  SCB->CPACR |= (0x3 << 10 * 2) | (0x3 << 11 * 2);
  Clock_Init();
  Uart2_Init(baud);
  setvbuf(stdout, NULL, _IONBF, 0);
}

void Main(void)
{
  char line[64];
  unsigned int length = 0;

  Sys_Init(115200);
  printf("\nSTM32_F411_UART2_READY\n");

  for (;;)
  {
    char data;

    while (!Macro_Check_Bit_Set(USART2->SR, 5))
      ;
    data = (char)USART2->DR;

    if (data == '\r')
      continue;

    if (data == '\n')
    {
      line[length] = '\0';
      printf("STM32_ACK:%s\n", line);
      length = 0;
      continue;
    }

    if (length < sizeof(line) - 1)
      line[length++] = data;
    else
      length = 0;
  }
}
