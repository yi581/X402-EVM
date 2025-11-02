/**
 * X402 一行代码集成示例
 *
 * 这是最简单的集成方式，真的只需要一行代码！
 */

// ============ 方式1：直接使用 ============

// 一行代码完成支付和获取数据
const getWeather = async () => await require('./simplest-client').payAndGet('http://localhost:3001/api/weather');

// 使用
getWeather().then(console.log).catch(console.error);

// ============ 方式2：在Express应用中 ============

const express = require('express');
const app = express();

// 原来的代码（不支持付费API）
app.get('/old-way', async (req, res) => {
    const response = await fetch('http://api.example.com/data');
    res.json(await response.json());
});

// 新的代码（支持X402付费，只改了一行！）
app.get('/new-way', async (req, res) => {
    res.json(await require('./simplest-client').payAndGet('http://localhost:3001/api/weather'));
});

// ============ 方式3：更简单的包装 ============

// 创建一个全局函数
global.x402 = url => require('./simplest-client').payAndGet(url);

// 现在在任何地方都可以使用
async function myApp() {
    const weather = await x402('http://localhost:3001/api/weather');
    const rate = await x402('http://localhost:3003/api/rate/usd');
    const ai = await x402('http://localhost:3004/api/ai/text');

    console.log({ weather, rate, ai });
}

// ============ 方式4：Promise链式调用 ============

require('./simplest-client')
    .payAndGet('http://localhost:3001/api/weather')
    .then(data => console.log('Weather:', data))
    .catch(err => console.error('Error:', err));

// ============ 方式5：同步风格（使用top-level await）============

// 在支持top-level await的环境中
// const data = await require('./simplest-client').payAndGet('http://localhost:3001/api/weather');

// ============ 集成难度对比 ============

console.log(`
集成难度对比：

普通HTTP请求:
const data = await fetch(url).then(r => r.json());

X402支付请求:
const data = await x402(url);

区别：只是把 fetch 换成 x402！

就是这么简单！
`);

// ============ 导出便捷函数 ============

module.exports = {
    // 最简单的导出，用户只需要这一个函数
    pay: url => require('./simplest-client').payAndGet(url)
};

// 用户使用：
// const { pay } = require('./one-line-integration');
// const data = await pay('http://any-x402-api.com/endpoint');