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
            {code = "Beijing", name = "北京", cities = {"Beijing", "Chaoyang", "Haidian", "Fengtai", "Shijingshan", "Tongzhou", "Changping", "Daxing", "Fangshan", "Mentougou", "Shunyi", "Pinggu", "Huairou", "Miyun", "Yanqing", "Yanqing"}},
            {code = "Tianjin", name = "天津", cities = {"Tianjin", "Heping", "Hedong", "Hexi", "Nankai", "Hebei", "Hongqiao", "Dongli", "Xiqing", "Jinnan", "Beichen", "Wuqing", "Baodi", "Jinghai", "Ninghe", "Jixian"}},
            {code = "Hebei", name = "河北", cities = {"Shijiazhuang", "Tangshan", "Qinhuangdao", "Handan", "Xingtai", "Baoding", "Zhangjiakou", "Chengde", "Cangzhou", "Langfang", "Hengshui"}},
            {code = "Shanxi", name = "山西", cities = {"Taiyuan", "Datong", "Yangquan", "Changzhi", "Jincheng", "Shuozhou", "Jinzhong", "Yuncheng", "Xinzhou", "Linfen", "Lvliang"}},
            {code = "Inner Mongolia", name = "内蒙古", cities = {"Hohhot", "Baotou", "Wuhai", "Chifeng", "Tongliao", "Ordos", "Hulunbuir", "Bayannur", "Ulanqab", "Xingan", "Xilin Gol", "Alxa"}}
        }
    },
    {
        region = "东北地区",
        provinces = {
            {code = "Liaoning", name = "辽宁", cities = {"Shenyang", "Dalian", "Anshan", "Fushun", "Benxi", "Dandong", "Jinzhou", "Yingkou", "Fuxin", "Liaoyang", "Panjin", "Tieling", "Chaoyang", "Huludao"}},
            {code = "Jilin", name = "吉林", cities = {"Changchun", "Jilin", "Siping", "Liaoyuan", "Tonghua", "Baishan", "Songyuan", "Baicheng", "Yanbian"}},
            {code = "Heilongjiang", name = "黑龙江", cities = {"Harbin", "Qiqihar", "Jixi", "Hegang", "Shuangyashan", "Daqing", "Yichun", "Jiamusi", "Qitaihe", "Mudanjiang", "Heihe", "Suihua", "Daxinganling"}}
        }
    },
    {
        region = "华东地区",
        provinces = {
            {code = "Shanghai", name = "上海", cities = {"Shanghai", "Huangpu", "Xuhui", "Changning", "Jingan", "Putuo", "Hongkou", "Yangpu", "Minhang", "Baoshan", "Jiading", "Pudong", "Jinshan", "Songjiang", "Qingpu", "Fengxian", "Chongming"}},
            {code = "Jiangsu", name = "江苏", cities = {"Nanjing", "Wuxi", "Xuzhou", "Changzhou", "Suzhou", "Nantong", "Lianyungang", "Huai'an", "Yancheng", "Yangzhou", "Zhenjiang", "Taizhou", "Suqian"}},
            {code = "Zhejiang", name = "浙江", cities = {"Hangzhou", "Ningbo", "Wenzhou", "Jiaxing", "Huzhou", "Shaoxing", "Jinhua", "Quzhou", "Zhoushan", "Taizhou", "Lishui"}},
            {code = "Anhui", name = "安徽", cities = {"Hefei", "Wuhu", "Bengbu", "Huainan", "Ma'anshan", "Huaibei", "Tongling", "Anqing", "Huangshan", "Chuzhou", "Fuyang", "Suzhou", "Lu'an", "Bozhou", "Chizhou", "Xuancheng"}},
            {code = "Fujian", name = "福建", cities = {"Fuzhou", "Xiamen", "Putian", "Sanming", "Quanzhou", "Zhangzhou", "Nanping", "Longyan", "Ningde"}},
            {code = "Jiangxi", name = "江西", cities = {"Nanchang", "Jingdezhen", "Pingxiang", "Jiujiang", "Xinyu", "Yingtan", "Ganzhou", "Ji'an", "Yichun", "Fuzhou", "Shangrao"}},
            {code = "Shandong", name = "山东", cities = {"Jinan", "Qingdao", "Zibo", "Zaozhuang", "Dongying", "Yantai", "Weifang", "Jining", "Taian", "Weihai", "Rizhao", "Linyi", "Dezhou", "Liaocheng", "Binzhou", "Heze"}}
        }
    },
    {
        region = "华中地区",
        provinces = {
            {code = "Henan", name = "河南", cities = {"Zhengzhou", "Kaifeng", "Luoyang", "Pingdingshan", "Anyang", "Hebi", "Xinxiang", "Jiaozuo", "Puyang", "Xuchang", "Luohe", "Sanmenxia", "Nanyang", "Shangqiu", "Xinyang", "Zhoukou", "Zhumadian", "Jiyuan"}},
            {code = "Hubei", name = "湖北", cities = {"Wuhan", "Huangshi", "Shiyan", "Yichang", "Xiangyang", "Ezhou", "Jingmen", "Xiaogan", "Jingzhou", "Huanggang", "Xianning", "Suizhou", "Enshi", "Xiantao", "Qianjiang", "Tianmen", "Shennongjia"}},
            {code = "Hunan", name = "湖南", cities = {"Changsha", "Zhuzhou", "Xiangtan", "Hengyang", "Shaoyang", "Yueyang", "Changde", "Zhangjiajie", "Yiyang", "Chenzhou", "Yongzhou", "Huaihua", "Loudi", "Xiangxi"}}
        }
    },
    {
        region = "华南地区",
        provinces = {
            {code = "Guangdong", name = "广东", cities = {"Guangzhou", "Shaoguan", "Shenzhen", "Zhuhai", "Shantou", "Foshan", "Jiangmen", "Zhanjiang", "Maoming", "Zhaoqing", "Huizhou", "Meizhou", "Shanwei", "Heyuan", "Yangjiang", "Qingyuan", "Dongguan", "Zhongshan", "Chaozhou", "Jieyang", "Yunfu"}},
            {code = "Guangxi", name = "广西", cities = {"Nanning", "Liuzhou", "Guilin", "Wuzhou", "Beihai", "Fangchenggang", "Qinzhou", "Guigang", "Yulin", "Baise", "Hezhou", "Hechi", "Laibin", "Chongzuo"}},
            {code = "Hainan", name = "海南", cities = {"Haikou", "Sanya", "Sansha", "Danzhou", "Wuzhishan", "Wenchang", "Qionghai", "Wanning", "Dongfang", "Ding'an", "Tunchang", "Chengmai", "Lingao", "Baisha", "Changjiang", "Ledong", "Lingshui", "Baoting", "Qiongzhong"}}
        }
    },
    {
        region = "特别行政区",
        provinces = {
            {code = "Taiwan", name = "台湾", cities = {"Taipei", "New Taipei", "Taoyuan", "Taichung", "Tainan", "Kaohsiung", "Keelung", "Hsinchu", "Chiayi", "Hsinchu County", "Miaoli", "Changhua", "Nantou", "Yunlin", "Chiayi County", "Pingtung", "Yilan", "Hualien", "Taitung", "Penghu", "Kinmen", "Lienchiang"}},
            {code = "Hong Kong", name = "香港", cities = {"Hong Kong", "Central and Western", "Wan Chai", "Eastern", "Southern", "Yau Tsim Mong", "Sham Shui Po", "Kowloon City", "Wong Tai Sin", "Kwun Tong", "Kwai Tsing", "Tsuen Wan", "Tuen Mun", "Yuen Long", "North", "Tai Po", "Sha Tin", "Sai Kung", "Islands"}},
            {code = "Macau", name = "澳门", cities = {"Macau", "Macao Peninsula", "Taipa", "Coloane", "Cotai"}}
        }
    },
    {
        region = "西南地区",
        provinces = {
            {code = "Chongqing", name = "重庆", cities = {"Chongqing", "Wanzhou", "Fuling", "Yuzhong", "Dadukou", "Jiangbei", "Shapingba", "Jiulongpo", "Nan'an", "Beibei", "Qijiang", "Dazu", "Bishan", "Tongnan", "Tongliang", "Rongchang", "Liangping", "Chengkou", "Fengdu", "Dianjiang", "Wulong", "Zhongxian", "Kaixian", "Yunyang", "Fengjie", "Wushan", "Wuxi", "Shizhu", "Pengshui", "Youyang", "Xiushan", "Qianjiang"}},
            {code = "Sichuan", name = "四川", cities = {"Chengdu", "Zigong", "Panzhihua", "Luzhou", "Deyang", "Mianyang", "Guangyuan", "Suining", "Neijiang", "Leshan", "Nanchong", "Meishan", "Yibin", "Guang'an", "Dazhou", "Ya'an", "Bazhong", "Ziyang", "Aba", "Ganzi", "Liangshan"}},
            {code = "Guizhou", name = "贵州", cities = {"Guiyang", "Liupanshui", "Zunyi", "Anshun", "Bijie", "Tongren", "Qianxinan", "Qiannan", "Qiandongnan"}},
            {code = "Yunnan", name = "云南", cities = {"Kunming", "Qujing", "Yuxi", "Baoshan", "Zhaotong", "Lijiang", "Pu'er", "Lincang", "Chuxiong", "Honghe", "Wenshan", "Xishuangbanna", "Dali", "Dehong", "Nujiang", "Diqing"}},
            {code = "Tibet", name = "西藏", cities = {"Lhasa", "Changdu", "Shannan", "Rikaze", "Naqu", "Ali", "Linzhi"}}
        }
    },
    {
        region = "西北地区",
        provinces = {
            {code = "Shaanxi", name = "陕西", cities = {"Xi'an", "Tongchuan", "Baoji", "Xianyang", "Weinan", "Yan'an", "Hanzhong", "Yulin", "Ankang", "Shangluo"}},
            {code = "Gansu", name = "甘肃", cities = {"Lanzhou", "Jiayuguan", "Jinchang", "Baiyin", "Tianshui", "Wuwei", "Zhangye", "Pingliang", "Jiuquan", "Qingyang", "Dingxi", "Longnan", "Linxia", "Gannan"}},
            {code = "Qinghai", name = "青海", cities = {"Xining", "Haidong", "Haibei", "Huangnan", "Hainan", "Guoluo", "Yushu", "Haixi"}},
            {code = "Ningxia", name = "宁夏", cities = {"Yinchuan", "Shizuishan", "Wuzhong", "Guyuan", "Zhongwei"}},
            {code = "Xinjiang", name = "新疆", cities = {"Urumqi", "Karamay", "Turpan", "Hami", "Changji", "Bortala", "Bayingol", "Aksu", "Kizilsu", "Kashgar", "Hotan", "Ili", "Tacheng", "Altay", "Shihezi", "Alar", "Tumushuke", "Wujiaqu", "Beitun", "Tiemenguan", "Shuanghe", "Kokdala", "Kunyu"}}
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

