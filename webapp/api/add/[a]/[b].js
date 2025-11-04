// webapp/api/add/[a]/[b].js
const sum = require('../../../sum');

module.exports = (req, res) => {
  const { a, b } = req.query; // vienen de /api/add/:a/:b
  const x = Number(a), y = Number(b);
  if (Number.isNaN(x) || Number.isNaN(y)) {
    res.statusCode = 400;
    return res.json({ error: 'Invalid numbers' });
  }
  return res.json({ result: sum(x, y) });
};
