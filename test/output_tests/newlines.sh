#!/bin/sh

# Ideally, all three of these will give the same result according to lines
printf "marco\npolo\n"
sleep .3
printf "marco\r"
sleep .3
printf "polo\r"
sleep .3
printf "marco\r\npolo\r\n"
