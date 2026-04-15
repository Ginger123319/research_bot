# 这是我新构建的一个项目，目前的主要目标是公司内部模型部署服务的迁移相关工作内容，我想借助 来对当前项目进行行动代号构建 "guofan...
_Exported on 2026/3/9 at GMT+8 20:03:53 from Cursor (transcript)_

---

**User**

这是我新构建的一个项目，目前的主要目标是公司内部模型部署服务的迁移相关工作内容，我想借助 https://zh.wikipedia.org/wiki/%E4%B8%8B%E5%8D%97%E6%B4%8B  来对当前项目进行行动代号构建 "guofan" means "过番"。
目前我将我负责的内容为

deployment（运维）	model	AIData日志（刘尧-临时列）	迁移决策	迁移优先级	迁移进度	工程组改造进度	算法负责人	Infra负责人	数据准备进度	迁移备注	当前是否为裸模型	拆成裸模型预期完成时间	总卡数	副本数	副本卡数	参数量	扩缩容策略	Pulsar部署平台服务名称	新服务地址	推理框架	镜像版本	cpu核数+内存大小+共享内存大小	开始迁移日期	申请资源规格	资源申请日期	资源到位日期	部署完成日期	切流完成日期	旧资源释放日期	Deploy名称（算法）	状态	total_max_rpm	stream_max_rpm	non_stream_max_rpm	仅在组内使用	自研模型部署时的模型名	模型基座	IP Address: Port	健康监测	服务类型	项目名	业务线L2	业务线L3	备注
tianji-query-safety-4b-v1-1-cmic	tianji-querysafety-4b-v2-3	AIData不支持，工程手动取260303-260304的日志	直接迁移：裸模型部署	高优	待开始		@刘尧	王倪东	未开始		1		32	8	4		无			sglang										tianji-query-safety-4b-v1-1-cmic-xxx	上线	567	0	567	否	tianji-querysafety-4b-v2-3	Qwen3-4B-Instruct-2507	http://172.21.64.30:8361	/health	自研裸模	天玑-Query安全改写	AI业务中心基建	天玑	251103: 4张卡部署1个节点，共需8个节点，即共需4*8=32张卡
sglang-tianji-v2-364-ceceproficient-model	wangshu-72b-v2	支持	延后迁移：裸模型部署，将要下线，被替换	低优	待开始		@黄继豪@刘奇	王倪东	未开始		1		16	2	8		无			sglang										sglang-tianji-v2-364-ceceproficient-model-cb686bfd7	上线	28	16	12	否	Tj_v2_364	qwen2.5	172.21.64.30:6666	/health		天玑-闲聊	AI业务中心基建	天玑	
xinghan-ziwei-32b-v1-cm	xinghan-ziwei-32b-v1-1	支持，已经取完数	直接迁移：分离部署	高优	待开始	测试	@刘奇	王倪东	未开始	马上交接和交接中的，建议等交接完了（交接的过程中，会拆分出裸模型）	0	紫微已经交接给工程后，自动就是“拆好的”	16	2	8		无			sglang										xinghan-ziwei-32b-v1	上线				否	xinghan-ziwei-32b-v1	qwen2.5-32b	"模型：http://172.21.64.30:5290 
意图： http://172.21.64.30:5291 
cpu服务：http://172.21.64.30:5292"	/health	调用自研裸模的服务	紫微-普通-32B	测测及测测达人	紫微	
ziwei-intention-twostep-8b-v1-cm	未知	算法内部服务，直接原资源量迁移，不用压测	直接迁移：裸模型部署	高优	待开始		@刘奇	王倪东	未开始		1		4	4	1		无																																																		

相关服务迁移部署，所以先在@README.md  将项目的目标跟动机先写一个，在之后的3周内我们会在该项目上进行很多脚本话测试调用来进行模型迁移评估工作。当前主要是做好铺垫。

---

**Cursor**

The user wants me to create a README.md for their project "guofan" (过番), which is about internal model deployment service migration work. They want me to use the "下南洋" (going to Southeast Asia) metaphor as the project's code name motivation.

Let me first check if there's already a README.md in the workspace.

---

**Cursor**

README.md 已写好。整体围绕「过番/下南洋」的文化典故展开，主要内容包括：

**行动代号释义** —— 以闽南「过番」下南洋的历史典故作为项目精神底色，旧土难以为继、整装出发、在新平台落地生根，与模型部署迁移的语境高度契合。

**项目动机与目标** —— 明确了统一推理框架（SGLang）、裸模型化、可观测性建设、平滑切流、旧资源有序释放五大方向。

**迁移范围总览** —— 将你提供的四个服务整理成表格，按优先级排列，清晰展示迁移策略与业务归属。

**3周工作计划** —— 分阶段拆解近期工作重心：环境搭建与部署验证 → 压测与性能基线 → 评估报告与切流决策。

**关键字段说明 & 联系人** —— 为后续协作和脚本开发提供参照。

末尾以一句「番客不怕苦，落番才有路」收尾，与行动代号呼应。

---
