### Xray-Alpine 安装脚本 amd64(x64) only
从XTLS官方的Alpine脚本而来，去除了其中的解压步骤，使用Github Actions预先从官方解压得到的二进制。目的是避免小内存机器解压导致OOM。