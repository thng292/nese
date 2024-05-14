import sys

class cpuState:
    instruction: str
    a: str
    x: str
    y: str
    flag: str
    cyc: str

def parseMe(line: str) -> cpuState:
    res = cpuState()
    res.instruction = line[5:8]
    res.a = line[40:42]
    res.x = line[45:47]
    res.y = line[50:52]
    res.flag = line[61:63]
    res.cyc = line[line.find('CYC:'):].strip()
    return res

def parseThey(line: str) -> cpuState:
    res = cpuState()
    res.instruction = line[16:19]
    res.a = line[50:52]
    res.x = line[55:57]
    res.y = line[60:62]
    res.flag = line[65:67]
    res.cyc = line[line.find('CYC:'):].strip()
    return res

def main():
    if len(sys.argv) != 3:
        print("Usage: python cmp.py <filename1> <filename2>")
    me = open(sys.argv[1])
    they = open(sys.argv[2])
    count = 0
    for mel, theyl in zip(me, they):
        count += 1
        a = parseMe(mel)
        b = parseThey(theyl)
        if a.instruction != b.instruction:# or a.cyc != b.cyc or a.a != b.a or a.x != b.x or a.y != b.y or a.flag != b.flag:
            print("File: File 1 | File 2")
            print("Instruction:", a.instruction, b.instruction)
            print('A:',a.a, b.a)
            print('X:',a.x, b.x)
            print('Y:',a.y, b.y)
            print('Flag:',a.flag, b.flag)
            print('CYC:',a.cyc, b.cyc)
            print("At line: ", count)
            print(mel)
            print(theyl)
            return

main()