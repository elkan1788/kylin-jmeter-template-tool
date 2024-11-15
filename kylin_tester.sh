#!/bin/bash
# 
# 执行Kylin查询请求自动化测试的脚本
#
# Author: 凡梦星尘 | elkan1788@139.com
# Date: 2024-11-13
# Version: 2.4.0
set -e

# JMeter执行文件根目录
ROOT=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

# 执行测试的参数
USERS=1
RAMP_TIME=5
LOOP_COUNT=-1
DURATION_TIME=30
COMPLEX_RATION=10
DEBUG_ON="false"

# Kylin 参数配置
DEF_CONF_FILE="conf.ini"
CONF_FILE=$DEF_CONF_FILE
PROTOCOL="http"
KYLIN_HOST="127.0.0.1"
KYLIN_PORT="7070"
KYLIN_USER="ADMIN"
KYLIN_PSWD="KYLIN"
KYLIN_PROJ="learn_kylin"
B64_AUTH="QURNSU46S1lMSU4="
LIMIT_MIN=1
LIMIT_MAX=500

# 测试报告输出
DEF_JMETER_SCRIPT="scripts/kylin-http-stress-template.jmx"
JMETER_SCRIPT=$DEF_JMETER_SCRIPT
DEF_SQL_CSV_FILE="scripts/kylin-query-sqls.csv"
SQL_CSV_FILE=$DEF_SQL_CSV_FILE
REPORT_OUTPUT_NAME=""
REPORT_OUTPUT_ROOT="report/"
REPORT_OUTPUT_DIR=""
REPORT_OUTPUT_LOG=".log"
REPORT_OUTPUT_JTL=".jtl"

# 简易WEB服务
PYTHON_CMD="python"
PY_ENV_VER=2
REPORT_SERVER_IP="127.0.0.1"
REPORT_SERVER_PORT=9999
REPORT_SERVER_PID="REPORT_SERVER_PID"

# 检查运行环境
function checkEnv() {
  
echo "JMeter压测工具的安装目录为：$ROOT"
  
# 检查是否存在JMeter执行文件
JMETER_BIN="./bin/jmeter.sh"
if [ ! -f $JMETER_BIN ]; then
  echo -e "\033[31m未找到JMeter的可执行文件\033[0m，请检查是否使用标准的Apache JMeter测试工具!!!" && exit 1
fi

# 检查工具是否已安装
NEED_TOOLS=("ps" "java" "netstat" "hostname")

for tool in "${NEED_TOOLS[@]}"; do
  if ! command -v $tool &> /dev/null; then
    echo -e "未找到必要的工具：\033[31m$tool\033[0m，请确保其已安装!!!" && exit 1
  fi
done

# 检查 Python 命令和版本
if command -v $PYTHON_CMD &> /dev/null; then
  PYTHON_CMD="python"
elif command -v python3 &> /dev/null; then
  PYTHON_CMD="python3"
else
  echo -e "未找到必要的工具：\033[31mpython 或 python3\033[0m，请确保已安装!!!" && exit 1
fi

PY_ENV_VER=$($PYTHON_CMD -V 2>&1 | grep -Po '(?<=Python )\d+\.\d+')
REPORT_SERVER_IP=$(hostname -I | awk '{print $1}')

if [ ! -d $REPORT_OUTPUT_ROOT ]; then
  mkdir $REPORT_OUTPUT_ROOT
fi

}

# 输出参数说明
function help() {
  echo "示例: kylin_tester.sh [options]"
  echo "命令:"
  echo "  -i   KYLIN配置参数文件的相对路径"
  echo "  -q   KYLIN查询SQL文件的相对路径"
  echo "  -j   JMeter测试脚本的相对路径"
  echo "  -o   测试结果输出名称，包括日志名称，脚本记录，HTML报告"
  echo "  -u   并发测试用户数，默认为：1"
  echo "  -l   测试轮循次数，默认为-1，表示使用持续时间方式"
  echo "  -r   并发测试用户唤起时间，单位：秒，默认为5秒"
  echo "  -d   并发测试的持续时间，单位：秒，默认为30秒"
  echo "  -c   复杂SQL执行比例（0-100），默认为10"
  echo "  -b   是否开启Debug模式，默认为false"
  echo "  -e   用Base64加密认证信息，用:号隔开用户与密码"
  echo "  -w   启停简易WEB服务，可选操作：start|stop"
}

# 启动简易WEB服务
function startWebServer() {

  local CHECK_PORT_USED=$(netstat -ano | grep ":$REPORT_SERVER_PORT")
  if [ -n "$CHECK_PORT_USED" ]; then  
    echo -e "\033[31m请检查，端口号${REPORT_SERVER_PORT}已被占用!!!\033[0m"  
    exit 1      
  fi

  cd report
  if [[ $PY_ENV_VER =~ ^3 ]]; then
    nohup $PYTHON_CMD -m http.server $REPORT_SERVER_PORT > /dev/null 2>&1 &
  else
    nohup $PYTHON_CMD -m SimpleHTTPServer $REPORT_SERVER_PORT > /dev/null 2>&1 &
  fi
  
  local PID=$!
  echo "$PID" > ../$REPORT_SERVER_PID
  echo -e "测试报告的WEB服务\033[32m已启动成功\033[0m，进程ID为：\033[36m $PID \033[0m"
  echo "请打开浏览器访问: http://$REPORT_SERVER_IP:$REPORT_SERVER_PORT/"
}

# 停止简易WEB服务
function stopWebServer() {

  if [ -f $REPORT_SERVER_PID ]; then
    local PID=$(cat $REPORT_SERVER_PID)
    if kill -0 $PID > /dev/null 2>&1; then
      kill -9 $PID
      rm -rf ./$REPORT_SERVER_PID
      echo -e "测试报告的WEB服务\033[32m已成功停止\033[0m"
    else
      echo -e "测试报告的WEB服务\033[33m未在运行\033[0m"
      rm -rf ./$REPORT_SERVER_PID
    fi
  else
    echo -e "测试报告的WEB服务\033[33m未在运行\033[0m"
  fi
}

# 检查文件是否存在
function checkFileExists() {
  local FILE_PATH=$1
  local DEFAULT_FILE_PATH=$2
  local FILE_NAME=$3
  local IsExist=1

  if [ -n "$FILE_PATH" ] && [ ! -f "$FILE_PATH" ] && [ "$FILE_PATH" != "$DEFAULT_FILE_PATH" ]; then
    IsExist=0
  elif [ -n "$DEFAULT_FILE_PATH" ] && [ ! -f "$DEFAULT_FILE_PATH" ]; then
    IsExist=0
    FILE_PATH=$DEFAULT_FILE_PATH
  fi
  
  if [ $IsExist -eq 0 ]; then
    echo -e "提示：请检查\033[31m${FILE_NAME}\033[0m路径配置是否正确!!!"
    echo -e "      当前\033[31m${FILE_NAME}\033[0m路径为：\033[31m$FILE_PATH\033[0m" && exit 1
  fi
}

# 检查JMeter测试必要的参数
function checkArgs() {

  checkFileExists $CONF_FILE $DEF_CONF_FILE "Kylin配置参数文件"
  checkFileExists $JMETER_SCRIPT $DEF_JMETER_SCRIPT "JMeter测试脚本"
  checkFileExists $SQL_CSV_FILE $DEF_SQL_CSV_FILE "SQL文件"

  # 根据时间生成报告名称
  if [ -z "$REPORT_OUTPUT_NAME" ]; then
    current_ts=$(date +%Y%m%d%H%M%S)
    if [ $LOOP_COUNT -eq -1 ]; then
      REPORT_OUTPUT_NAME="users${USERS}_${DURATION_TIME}s_${current_ts}"
    else
      REPORT_OUTPUT_NAME="users${USERS}_${LOOP_COUNT}l_${current_ts}"
    fi
  fi

  REPORT_OUTPUT_DIR="$REPORT_OUTPUT_ROOT$REPORT_OUTPUT_NAME"
  REPORT_OUTPUT_LOG="$REPORT_OUTPUT_DIR$REPORT_OUTPUT_LOG"
  REPORT_OUTPUT_JTL="$REPORT_OUTPUT_DIR$REPORT_OUTPUT_JTL"

  # 当有已存在报告时退出，JMeter报告暂不支持覆盖操作
  if [ -f "$REPORT_OUTPUT_LOG" ] || [ -f "$REPORT_OUTPUT_JTL" ] || [ -d "$REPORT_OUTPUT_DIR" ]; then
    echo -e "提示：请检查JMeter测试结果输出名称是否已存在!!!"
    echo -e "      路径为：\033[31m $REPORT_OUTPUT_DIR \033[0m" 
    echo -e "      日志为：\033[31m $REPORT_OUTPUT_LOG \033[0m" 
    echo -e "      记录为：\033[31m $REPORT_OUTPUT_JTL \033[0m"  && exit 1
  fi

  echo -e " Kylin配置为：\033[36m $CONF_FILE \033[0m"
  echo -e "   SQL文件为：\033[36m $SQL_CSV_FILE \033[0m"
  echo -e "测试的脚本为：\033[36m $JMETER_SCRIPT \033[0m"
  echo -e "测试报告输出：\033[36m $REPORT_OUTPUT_DIR \033[0m"
  echo -e "测试日志文件：\033[36m $REPORT_OUTPUT_LOG \033[0m"
  echo -e "测试记录文件：\033[36m $REPORT_OUTPUT_JTL \033[0m"

}

# 替换JMeter的设置
function replaceSets() {

  if [ "$DEBUG_ON" = "false" ]; then
    # 关闭对返回代码的断言
    sed -i \
      -e '/testname="Result Code Assertion" enabled="true"/s/true/false/g' \
      -e '/testname="Except Mesg Assertion" enabled="true"/s/true/false/g' \
      $JMETER_SCRIPT
  else
    # 开启对返回代码的断言
    echo -e "\033[31m请注意正在使用Debug模式，建议在正式测试时关闭!!!\033[0m"
    sed -i \
      -e '/testname="Result Code Assertion" enabled="false"/s/false/true/g' \
      -e '/testname="Except Mesg Assertion" enabled="false"/s/false/true/g' \
      $JMETER_SCRIPT
  fi

  # 根据不同测试方式设置参数
  if [ $LOOP_COUNT -eq -1 ]; then
    echo "持续时长为：${DURATION_TIME}s"
    sed -i '/<boolProp name="ThreadGroup.scheduler">false<\/boolProp>/s/false/true/g' $JMETER_SCRIPT
  else
    echo "循环次数为：$LOOP_COUNT"
    sed -i '/<boolProp name="ThreadGroup.scheduler">true<\/boolProp>/s/true/false/g' $JMETER_SCRIPT
  fi

}

# BASE64算法加密
function encryptB64 () {

  local IS_EMPTY=$( [ -z "$1" ] && echo "0" || echo "1" )

  if [[ $IS_EMPTY -eq 1 ]]; then
    B64_AUTH=$1
  else
    B64_AUTH=$KYLIN_USER":"$KYLIN_PSWD
  fi

  B64_AUTH=$(echo -n "$B64_AUTH" | base64)

  if [[ $IS_EMPTY -eq 1 ]]; then
    echo -e "Base64加密的结果为：\033[32m$B64_AUTH\033[0m"
  fi
}

# 提交测试任务
function start() {
  
  echo "并发用户数为：$USERS"
  nohup $JMETER_BIN \
    -Jsqlfile=$ROOT"/"$SQL_CSV_FILE \
    -Jhost=$KYLIN_HOST \
    -Jport=$KYLIN_PORT \
    -Jb64auth=$B64_AUTH \
    -Jprojname=$KYLIN_PROJ \
    -Jlimitmin=$LIMIT_MIN \
    -Jlimitmax=$LIMIT_MAX \
    -Jusers=$USERS \
    -Jtime=$DURATION_TIME \
    -Jcration=$COMPLEX_RATION \
    -Jrtime=$RAMP_TIME \
    -Jloop=$LOOP_COUNT \
    -n -t $JMETER_SCRIPT \
    -l $REPORT_OUTPUT_JTL \
    -e -o $REPORT_OUTPUT_DIR > $REPORT_OUTPUT_LOG 2>/dev/null &
  
  local PID="$!"
  echo -e "此次测试任务\033[32m已成功提交\033[0m，进程ID为：\033[36m $PID \033[0m，详细测试过程如下："
  sleep 1s
  tail -f $REPORT_OUTPUT_LOG --pid $PID

  if ps -p $PID > /dev/null; then  
    echo -e "\033[31m测试发生未知异常，任务还在进行，正在进行强制结束...\033[0m"
    kill -9 $PID
  fi
  
  echo -e "\033[32m测试任务已完成\033[0m"
  echo "请打开查看测试报告：http://${REPORT_SERVER_IP}:${REPORT_SERVER_PORT}/${REPORT_OUTPUT_NAME}/index.html"

}

# 获取Kylin参数值
function getProps() {
  while IFS=":" read -r key value; do  
    case $key in  
      protocol)  
        PROTOCOL=$value  
        ;;
      kylin_host)  
        KYLIN_HOST=$value  
        ;;
      kylin_port)  
        KYLIN_PORT=$value  
        ;;
      kylin_user)  
        KYLIN_USER=$value  
        ;;
      kylin_pswd)  
        KYLIN_PSWD=$value  
        ;;
      kylin_proj)
        KYLIN_PROJ=$value
        ;;
      limit_min)
        LIMIT_MIN=$value
        ;;
      limit_max)
        LIMIT_MAX=$value
        ;;
      server_port)
        REPORT_SERVER_PORT=$value
        ;;
      *)
        echo -e "\033[31m未知参数配置：$key=$value \033[0m"
        ;;
    esac  
  done < "$CONF_FILE"
}

# 解析用户自定义测试参数
function parseArgs() {

  while getopts "i:q:j:o:u:l:r:d:c:b:w:e:h" opt; do
    case $opt in
    i)
      CONF_FILE=$OPTARG
      ;;
    q)
      SQL_CSV_FILE=$OPTARG
      ;;
    j)
      JMETER_SCRIPT=$OPTARG
      ;;
    o)
      REPORT_OUTPUT_NAME=$OPTARG
      ;;
    u)
      USERS=$OPTARG
      ;;
    l)
      LOOP_COUNT=$OPTARG
      ;;
    r)
      RAMP_TIME=$OPTARG
      ;;
    d)
      DURATION_TIME=$OPTARG
      ;;
    c)
      COMPLEX_RATION=$OPTARG
      ;;
    b)
      DEBUG_ON=$OPTARG
      ;;
    w)
      if [ "$OPTARG" == "start" ] && [ ! -f $REPORT_SERVER_PID ]; then
        startWebServer
      elif [ "$OPTARG" == "start" ] && [ -f $REPORT_SERVER_PID ]; then
        echo -e "测试报告的WEB服务\033[32m已在运行中\033[0m"
        echo -e "请在浏览器直接访问：\033[32mhttp://$REPORT_SERVER_IP:$REPORT_SERVER_PORT/\033[0m"
      elif [ "$OPTARG" == "stop" ] && [ -f $REPORT_SERVER_PID ]; then
        stopWebServer
      elif [ "$OPTARG" != "start" ] && [ "$OPTARG" != "stop" ]; then
        echo -e "发现使用了并不支持的参数：\033[31m$OPTARG\033[0m，请检查!!!"
      else
        echo "测试报告的WEB服务并未启动!!!"
      fi
      exit 0
      ;;
    e)
      encryptB64 $OPTARG
      exit 0
      ;;
    h)
      help
      exit 0
      ;;
    ?)
      echo -e "发现不支持的参数或变量: \033[31m$opt\033[0m" 
      help && exit 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

}

function main() {

  checkEnv
  
  parseArgs "$@"

  checkArgs
  getProps
  encryptB64
  replaceSets
  start

}

main "$@";