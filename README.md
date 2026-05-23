# pure_tcl

tcl语法windows和linux平台构建

## 文档

https://www.tcl-lang.org/man/tcl9.0/

## 环境部署

### windows

windows的UCRT64终端环境下需要设置下 PATH 环境变量。

- `.bashrc`

```bash
export PATH="/opt/tcl9/bin:$PATH"
```

- 终端环境下的中文处理

如果要在终端环境下处理中文，建议按照下面这样设置：

```bash
export LANG="zh_CN.UTF-8"
export LC_ALL="zh_CN.UTF-8"
chcp.com 65001 > /dev/null 2>&1
```

上面要设置 `zh_CN.UTF-8` 才能处理中文输入。

`C.utf8`：是给程序看的（保证程序读取 UTF-8 文件不崩），它不关心你的输入体验。
`zh_CN.UTF-8`：是给人看的（开启了完整的输入、排序、显示支持）。

## 包管理

### 引导文件生成

在包的目录下执行下面的命令，会自动生成：`pkgIndex.tcl`文件。

```tcl
echo "pkg_mkIndex . *.tcl" | tclsh9
```

但是，当前项目中`pkgIndex.tcl`已经手动编辑，所以不要在自动生成，因为顺序有要求。

## 自动化测试

- 执行所有的用例

```tcl
tclsh9 all.tcl
```

- 执行单个用例

```tcl
tclsh9 sys.test
tclsh9 log.test
```

## 外部工具

`src/tutils/tools` 目录下的工具需要提前部署到可执行目录中。

