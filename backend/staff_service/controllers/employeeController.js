// ==================================================
// controllers/employeeController.js
// PURPOSE: Employee CRUD (Payroll consumer)
// ==================================================

const Employee = require("../schemas/Employee");

// -------------------- CREATE --------------------
exports.createEmployee = async (req, res) => {
  try {
    const emp = await Employee.create(req.body);
    res.status(201).json(emp);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// -------------------- GET BY ID --------------------
exports.getEmployeeById = async (req, res) => {
  try {
    const emp = await Employee.findById(req.params.id);
    if (!emp) return res.status(404).json({ error: "Employee not found" });
    res.json(emp);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// -------------------- LIST --------------------
exports.listEmployees = async (req, res) => {
  try {
    const list = await Employee.find({ active: true });
    res.json(list);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// -------------------- UPDATE --------------------
exports.updateEmployee = async (req, res) => {
  try {
    const emp = await Employee.findByIdAndUpdate(req.params.id, req.body, {
      new: true,
    });
    if (!emp) return res.status(404).json({ error: "Employee not found" });
    res.json(emp);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// -------------------- DEACTIVATE --------------------
exports.deactivateEmployee = async (req, res) => {
  try {
    const emp = await Employee.findByIdAndUpdate(
      req.params.id,
      { active: false },
      { new: true }
    );
    if (!emp) return res.status(404).json({ error: "Employee not found" });
    res.json(emp);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
