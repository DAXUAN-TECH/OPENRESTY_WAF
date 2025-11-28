-- 地域数据API模块
-- 路径：项目目录下的 lua/api/geo.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供地域数据（国家、省份、城市）查询API

local api_utils = require "api.utils"
local cjson = require "cjson"
local auth = require "waf.auth"

local _M = {}

-- 国外国家数据（按洲分类）
local foreign_countries = {
    {
        continent = "亚洲",
        countries = {
            {code = "JP", name = "日本"},
            {code = "KR", name = "韩国"},
            {code = "IN", name = "印度"},
            {code = "TH", name = "泰国"},
            {code = "VN", name = "越南"},
            {code = "SG", name = "新加坡"},
            {code = "MY", name = "马来西亚"},
            {code = "ID", name = "印度尼西亚"},
            {code = "PH", name = "菲律宾"},
            {code = "BD", name = "孟加拉国"},
            {code = "PK", name = "巴基斯坦"},
            {code = "SA", name = "沙特阿拉伯"},
            {code = "AE", name = "阿联酋"},
            {code = "TR", name = "土耳其"},
            {code = "IL", name = "以色列"}
        }
    },
    {
        continent = "欧洲",
        countries = {
            {code = "GB", name = "英国"},
            {code = "DE", name = "德国"},
            {code = "FR", name = "法国"},
            {code = "IT", name = "意大利"},
            {code = "ES", name = "西班牙"},
            {code = "NL", name = "荷兰"},
            {code = "BE", name = "比利时"},
            {code = "CH", name = "瑞士"},
            {code = "AT", name = "奥地利"},
            {code = "SE", name = "瑞典"},
            {code = "NO", name = "挪威"},
            {code = "DK", name = "丹麦"},
            {code = "FI", name = "芬兰"},
            {code = "PL", name = "波兰"},
            {code = "RU", name = "俄罗斯"}
        }
    },
    {
        continent = "北美洲",
        countries = {
            {code = "US", name = "美国"},
            {code = "CA", name = "加拿大"},
            {code = "MX", name = "墨西哥"}
        }
    },
    {
        continent = "南美洲",
        countries = {
            {code = "BR", name = "巴西"},
            {code = "AR", name = "阿根廷"},
            {code = "CL", name = "智利"},
            {code = "CO", name = "哥伦比亚"},
            {code = "PE", name = "秘鲁"}
        }
    },
    {
        continent = "大洋洲",
        countries = {
            {code = "AU", name = "澳大利亚"},
            {code = "NZ", name = "新西兰"}
        }
    },
    {
        continent = "非洲",
        countries = {
            {code = "ZA", name = "南非"},
            {code = "EG", name = "埃及"},
            {code = "NG", name = "尼日利亚"},
            {code = "KE", name = "肯尼亚"}
        }
    }
}

-- 国内省份数据（按地区分类）
local china_provinces = {
    {
        region = "华北地区",
        provinces = {
            {code = "Beijing", name = "北京", cities = {"北京", "朝阳", "海淀", "丰台", "石景山", "通州", "昌平", "大兴", "房山", "门头沟", "顺义", "平谷", "怀柔", "密云", "延庆"}},
            {code = "Tianjin", name = "天津", cities = {"天津", "和平", "河东", "河西", "南开", "河北", "红桥", "东丽", "西青", "津南", "北辰", "武清", "宝坻", "静海", "宁河", "蓟县"}},
            {code = "Hebei", name = "河北", cities = {"石家庄", "唐山", "秦皇岛", "邯郸", "邢台", "保定", "张家口", "承德", "沧州", "廊坊", "衡水"}},
            {code = "Shanxi", name = "山西", cities = {"太原", "大同", "阳泉", "长治", "晋城", "朔州", "晋中", "运城", "忻州", "临汾", "吕梁"}},
            {code = "Inner Mongolia", name = "内蒙古", cities = {"呼和浩特", "包头", "乌海", "赤峰", "通辽", "鄂尔多斯", "呼伦贝尔", "巴彦淖尔", "乌兰察布", "兴安", "锡林郭勒", "阿拉善"}}
        }
    },
    {
        region = "东北地区",
        provinces = {
            {code = "Liaoning", name = "辽宁", cities = {"沈阳", "大连", "鞍山", "抚顺", "本溪", "丹东", "锦州", "营口", "阜新", "辽阳", "盘锦", "铁岭", "朝阳", "葫芦岛"}},
            {code = "Jilin", name = "吉林", cities = {"长春", "吉林", "四平", "辽源", "通化", "白山", "松原", "白城", "延边"}},
            {code = "Heilongjiang", name = "黑龙江", cities = {"哈尔滨", "齐齐哈尔", "鸡西", "鹤岗", "双鸭山", "大庆", "伊春", "佳木斯", "七台河", "牡丹江", "黑河", "绥化", "大兴安岭"}}
        }
    },
    {
        region = "华东地区",
        provinces = {
            {code = "Shanghai", name = "上海", cities = {"上海", "黄浦", "徐汇", "长宁", "静安", "普陀", "虹口", "杨浦", "闵行", "宝山", "嘉定", "浦东", "金山", "松江", "青浦", "奉贤", "崇明"}},
            {code = "Jiangsu", name = "江苏", cities = {"南京", "无锡", "徐州", "常州", "苏州", "南通", "连云港", "淮安", "盐城", "扬州", "镇江", "泰州", "宿迁"}},
            {code = "Zhejiang", name = "浙江", cities = {"杭州", "宁波", "温州", "嘉兴", "湖州", "绍兴", "金华", "衢州", "舟山", "台州", "丽水"}},
            {code = "Anhui", name = "安徽", cities = {"合肥", "芜湖", "蚌埠", "淮南", "马鞍山", "淮北", "铜陵", "安庆", "黄山", "滁州", "阜阳", "宿州", "六安", "亳州", "池州", "宣城"}},
            {code = "Fujian", name = "福建", cities = {"福州", "厦门", "莆田", "三明", "泉州", "漳州", "南平", "龙岩", "宁德"}},
            {code = "Jiangxi", name = "江西", cities = {"南昌", "景德镇", "萍乡", "九江", "新余", "鹰潭", "赣州", "吉安", "宜春", "抚州", "上饶"}},
            {code = "Shandong", name = "山东", cities = {"济南", "青岛", "淄博", "枣庄", "东营", "烟台", "潍坊", "济宁", "泰安", "威海", "日照", "临沂", "德州", "聊城", "滨州", "菏泽"}}
        }
    },
    {
        region = "华中地区",
        provinces = {
            {code = "Henan", name = "河南", cities = {"郑州", "开封", "洛阳", "平顶山", "安阳", "鹤壁", "新乡", "焦作", "濮阳", "许昌", "漯河", "三门峡", "南阳", "商丘", "信阳", "周口", "驻马店", "济源"}},
            {code = "Hubei", name = "湖北", cities = {"武汉", "黄石", "十堰", "宜昌", "襄阳", "鄂州", "荆门", "孝感", "荆州", "黄冈", "咸宁", "随州", "恩施", "仙桃", "潜江", "天门", "神农架"}},
            {code = "Hunan", name = "湖南", cities = {"长沙", "株洲", "湘潭", "衡阳", "邵阳", "岳阳", "常德", "张家界", "益阳", "郴州", "永州", "怀化", "娄底", "湘西"}}
        }
    },
    {
        region = "华南地区",
        provinces = {
            {code = "Guangdong", name = "广东", cities = {"广州", "韶关", "深圳", "珠海", "汕头", "佛山", "江门", "湛江", "茂名", "肇庆", "惠州", "梅州", "汕尾", "河源", "阳江", "清远", "东莞", "中山", "潮州", "揭阳", "云浮"}},
            {code = "Guangxi", name = "广西", cities = {"南宁", "柳州", "桂林", "梧州", "北海", "防城港", "钦州", "贵港", "玉林", "百色", "贺州", "河池", "来宾", "崇左"}},
            {code = "Hainan", name = "海南", cities = {"海口", "三亚", "三沙", "儋州", "五指山", "文昌", "琼海", "万宁", "东方", "定安", "屯昌", "澄迈", "临高", "白沙", "昌江", "乐东", "陵水", "保亭", "琼中"}}
        }
    },
    {
        region = "特别行政区",
        provinces = {
            {code = "Taiwan", name = "台湾", cities = {"台北", "新北", "桃园", "台中", "台南", "高雄", "基隆", "新竹", "嘉义", "新竹县", "苗栗", "彰化", "南投", "云林", "嘉义县", "屏东", "宜兰", "花莲", "台东", "澎湖", "金门", "连江"}},
            {code = "Hong Kong", name = "香港", cities = {"香港", "中西区", "湾仔", "东区", "南区", "油尖旺", "深水埗", "九龙城", "黄大仙", "观塘", "葵青", "荃湾", "屯门", "元朗", "北区", "大埔", "沙田", "西贡", "离岛"}},
            {code = "Macau", name = "澳门", cities = {"澳门", "澳门半岛", "氹仔", "路环", "路氹城"}}
        }
    },
    {
        region = "西南地区",
        provinces = {
            {code = "Chongqing", name = "重庆", cities = {"重庆", "万州", "涪陵", "渝中", "大渡口", "江北", "沙坪坝", "九龙坡", "南岸", "北碚", "綦江", "大足", "璧山", "铜梁", "潼南", "荣昌", "梁平", "城口", "丰都", "垫江", "武隆", "忠县", "开县", "云阳", "奉节", "巫山", "巫溪", "石柱", "秀山", "酉阳", "彭水"}},
            {code = "Sichuan", name = "四川", cities = {"成都", "自贡", "攀枝花", "泸州", "德阳", "绵阳", "广元", "遂宁", "内江", "乐山", "南充", "眉山", "宜宾", "广安", "达州", "雅安", "巴中", "资阳", "阿坝", "甘孜", "凉山"}},
            {code = "Guizhou", name = "贵州", cities = {"贵阳", "六盘水", "遵义", "安顺", "毕节", "铜仁", "黔西南", "黔南", "黔东南"}},
            {code = "Yunnan", name = "云南", cities = {"昆明", "曲靖", "玉溪", "保山", "昭通", "丽江", "普洱", "临沧", "楚雄", "红河", "文山", "西双版纳", "大理", "德宏", "怒江", "迪庆"}},
            {code = "Tibet", name = "西藏", cities = {"拉萨", "昌都", "山南", "日喀则", "那曲", "阿里", "林芝"}}
        }
    },
    {
        region = "西北地区",
        provinces = {
            {code = "Shaanxi", name = "陕西", cities = {"西安", "铜川", "宝鸡", "咸阳", "渭南", "延安", "汉中", "榆林", "安康", "商洛"}},
            {code = "Gansu", name = "甘肃", cities = {"兰州", "嘉峪关", "金昌", "白银", "天水", "武威", "张掖", "平凉", "酒泉", "庆阳", "定西", "陇南", "临夏", "甘南"}},
            {code = "Qinghai", name = "青海", cities = {"西宁", "海东", "海北", "黄南", "海南", "果洛", "玉树", "海西"}},
            {code = "Ningxia", name = "宁夏", cities = {"银川", "石嘴山", "吴忠", "固原", "中卫"}},
            {code = "Xinjiang", name = "新疆", cities = {"乌鲁木齐", "克拉玛依", "吐鲁番", "哈密", "昌吉", "博尔塔拉", "巴音郭楞", "阿克苏", "克孜勒苏", "喀什", "和田", "伊犁", "塔城", "阿勒泰", "石河子", "阿拉尔", "图木舒克", "五家渠", "北屯", "铁门关", "双河", "可克达拉", "昆玉"}}
        }
    }
}

-- 获取所有地域数据
function _M.get_all()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    api_utils.json_response({
        success = true,
        data = {
            foreign = foreign_countries,
            china = china_provinces
        }
    }, 200)
end

-- 获取指定省份的城市列表
function _M.get_cities()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local province_code = args.province_code
    
    if not province_code then
        api_utils.json_response({
            success = false,
            error = "province_code is required"
        }, 400)
        return
    end
    
    -- 查找省份
    local cities = nil
    for _, region in ipairs(china_provinces) do
        for _, province in ipairs(region.provinces) do
            if province.code == province_code then
                cities = province.cities
                break
            end
        end
        if cities then
            break
        end
    end
    
    if not cities then
        api_utils.json_response({
            success = false,
            error = "Province not found"
        }, 404)
        return
    end
    
    api_utils.json_response({
        success = true,
        data = cities
    }, 200)
end

return _M

